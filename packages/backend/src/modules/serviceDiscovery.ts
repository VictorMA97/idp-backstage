import {
  coreServices,
  createBackendModule,
  readSchedulerServiceTaskScheduleDefinitionFromConfig,
} from '@backstage/backend-plugin-api';
import type { LoggerService } from '@backstage/backend-plugin-api';
import { DefaultGithubCredentialsProvider, ScmIntegrations } from '@backstage/integration';
import {
  catalogProcessingExtensionPoint,
  locationSpecToLocationEntity,
} from '@backstage/plugin-catalog-node';
import type { EntityProvider, EntityProviderConnection } from '@backstage/plugin-catalog-node';

// Descubre los repos de servicios (svc-*) de una cuenta de GitHub y los registra en el catálogo.
//
// Por qué no se usa el módulo oficial (catalog-backend-module-github): su consulta GraphQL lista TAMBIÉN
// los repos privados de la cuenta; con un token de solo lectura que no los cubre, GitHub responde con
// errores parciales y el módulo descarta la ejecución entera. Esta versión usa la API REST de repos
// PÚBLICOS (/users/{owner}/repos): no ve los privados y el token solo necesita leer repos públicos.

export type DiscoveryOptions = {
  owner: string;
  repositoryPattern: RegExp;
  catalogPath: string;
  baseUrl?: string;
};

type GithubRepo = {
  name: string;
  html_url: string;
  default_branch: string;
  archived: boolean;
  fork: boolean;
  private: boolean;
};

const MAX_PAGES = 20;

async function githubGet(
  fetchFn: typeof fetch,
  url: string,
  token?: string,
): Promise<Response> {
  return fetchFn(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
}

/**
 * Devuelve las URL de catalog-info.yaml de los repos que cumplen el patrón.
 * Si GitHub falla (red, límite de uso, token), LANZA: quien llama no debe aplicar una lista parcial,
 * porque una mutación completa con menos entidades borraría del catálogo las que faltan.
 */
export async function discoverCatalogUrls(
  opts: DiscoveryOptions,
  token: string | undefined,
  fetchFn: typeof fetch = fetch,
): Promise<string[]> {
  const api = opts.baseUrl ?? 'https://api.github.com';
  const repos: GithubRepo[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const res = await githubGet(
      fetchFn,
      `${api}/users/${encodeURIComponent(opts.owner)}/repos?type=owner&per_page=100&page=${page}`,
      token,
    );
    if (!res.ok) {
      throw new Error(`GitHub respondió ${res.status} al listar los repos de ${opts.owner}`);
    }
    const batch = (await res.json()) as GithubRepo[];
    repos.push(...batch);
    if (batch.length < 100) break;
  }

  const candidates = repos.filter(
    r =>
      opts.repositoryPattern.test(r.name) &&
      !r.private &&
      !r.archived &&
      !r.fork &&
      Boolean(r.default_branch),
  );

  const catalogPath = opts.catalogPath.replace(/^\//, '');
  const urls: string[] = [];
  for (const repo of candidates) {
    const res = await githubGet(
      fetchFn,
      `${api}/repos/${encodeURIComponent(opts.owner)}/${encodeURIComponent(repo.name)}/contents/${catalogPath}?ref=${encodeURIComponent(repo.default_branch)}`,
      token,
    );
    if (res.status === 404) continue; // el repo existe pero aún no tiene catalog-info.yaml
    if (!res.ok) {
      throw new Error(`GitHub respondió ${res.status} al comprobar ${repo.name}/${catalogPath}`);
    }
    urls.push(`${repo.html_url}/blob/${repo.default_branch}/${catalogPath}`);
  }
  return urls.sort();
}

class ServiceDiscoveryProvider implements EntityProvider {
  private connection?: EntityProviderConnection;
  private markConnected!: () => void;
  // La tarea programada puede dispararse antes de que el catálogo conecte el proveedor: se espera.
  private readonly connected = new Promise<void>(resolve => {
    this.markConnected = resolve;
  });

  constructor(
    private readonly id: string,
    private readonly opts: DiscoveryOptions,
    private readonly getToken: () => Promise<string | undefined>,
    private readonly logger: LoggerService,
  ) {}

  getProviderName() {
    return `service-discovery:${this.id}`;
  }

  async connect(connection: EntityProviderConnection) {
    this.connection = connection;
    this.markConnected();
  }

  async refresh() {
    await Promise.race([
      this.connected,
      new Promise<void>((_, reject) =>
        setTimeout(() => reject(new Error('El catálogo no conectó el proveedor a tiempo')), 60_000).unref(),
      ),
    ]);
    if (!this.connection) throw new Error('El proveedor no está conectado');
    const urls = await discoverCatalogUrls(this.opts, await this.getToken());
    this.logger.info(`Descubiertos ${urls.length} servicio(s) de ${this.opts.owner}: ${urls.join(', ') || '(ninguno)'}`);
    await this.connection.applyMutation({
      type: 'full',
      entities: urls.map(target => {
        const entity = locationSpecToLocationEntity({ location: { type: 'url', target } });
        return { entity, locationKey: this.getProviderName() };
      }),
    });
  }
}

export default createBackendModule({
  pluginId: 'catalog',
  moduleId: 'service-discovery',
  register(env) {
    env.registerInit({
      deps: {
        catalog: catalogProcessingExtensionPoint,
        config: coreServices.rootConfig,
        logger: coreServices.logger,
        scheduler: coreServices.scheduler,
      },
      async init({ catalog, config, logger, scheduler }) {
        const cfg = config.getOptionalConfig('idp.serviceDiscovery');
        if (!cfg) {
          logger.info('idp.serviceDiscovery no está configurado: descubrimiento de servicios desactivado');
          return;
        }
        const owner = cfg.getString('owner');
        const opts: DiscoveryOptions = {
          owner,
          repositoryPattern: new RegExp(cfg.getOptionalString('repositoryPattern') ?? '^svc-[a-z0-9-]+$'),
          catalogPath: cfg.getOptionalString('catalogPath') ?? '/catalog-info.yaml',
          baseUrl: cfg.getOptionalString('apiBaseUrl'), // solo para pruebas con un GitHub simulado
        };
        const credentials = DefaultGithubCredentialsProvider.fromIntegrations(ScmIntegrations.fromConfig(config));
        const provider = new ServiceDiscoveryProvider(
          'github',
          opts,
          async () => (await credentials.getCredentials({ url: `https://github.com/${owner}` })).token,
          logger,
        );
        catalog.addEntityProvider(provider);
        await scheduler.scheduleTask({
          id: 'service-discovery:github:refresh',
          ...readSchedulerServiceTaskScheduleDefinitionFromConfig(cfg.getConfig('schedule')),
          fn: async () => {
            try {
              await provider.refresh();
            } catch (e) {
              logger.error(`Descubrimiento de servicios fallido (el catálogo no se modifica): ${e}`);
              throw e;
            }
          },
        });
      },
    });
  },
});
