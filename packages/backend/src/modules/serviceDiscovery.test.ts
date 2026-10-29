import { discoverCatalogUrls } from './serviceDiscovery';

const opts = { owner: 'VictorMA97', repositoryPattern: /^svc-[a-z0-9-]+$/, catalogPath: '/catalog-info.yaml' };
const repo = (name: string, extra: object = {}) => ({
  name,
  html_url: `https://github.com/VictorMA97/${name}`,
  default_branch: 'main',
  archived: false,
  fork: false,
  private: false,
  ...extra,
});
const json = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

describe('discoverCatalogUrls', () => {
  it('devuelve solo repos svc-* públicos, activos, no fork y con catalog-info.yaml', async () => {
    const listed = [
      repo('svc-test'),
      repo('svc-sin-catalogo'),
      repo('svc-privado', { private: true }),
      repo('svc-archivado', { archived: true }),
      repo('svc-fork', { fork: true }),
      repo('idp-platform'),
      repo('svc-Mayus'),
    ];
    const fetchFn = jest.fn(async (url: string) => {
      if (url.includes('/users/')) return json(listed);
      if (url.includes('/svc-sin-catalogo/contents/')) return json({}, 404);
      return json({});
    });
    const urls = await discoverCatalogUrls(opts, 'tok', fetchFn as unknown as typeof fetch);
    expect(urls).toEqual(['https://github.com/VictorMA97/svc-test/blob/main/catalog-info.yaml']);
    const calls = fetchFn.mock.calls as unknown as Array<[string, { headers: Record<string, string> }]>;
    expect(calls.every(c => c[1].headers.Authorization === 'Bearer tok')).toBe(true);
  });

  it('lanza si GitHub falla, para no aplicar una lista parcial', async () => {
    const fetchFn = jest.fn(async (url: string) =>
      url.includes('/users/') ? json([repo('svc-a')]) : json({}, 502),
    );
    await expect(discoverCatalogUrls(opts, undefined, fetchFn as unknown as typeof fetch)).rejects.toThrow(/502/);
    const listFail = jest.fn(async () => json({}, 403));
    await expect(discoverCatalogUrls(opts, undefined, listFail as unknown as typeof fetch)).rejects.toThrow(/403/);
  });

  it('pagina', async () => {
    const page1 = Array.from({ length: 100 }, (_, i) => repo(`otro-${i}`));
    const fetchFn = jest.fn(async (url: string) => {
      if (url.endsWith('&page=1')) return json(page1);
      if (url.endsWith('&page=2')) return json([repo('svc-b')]);
      return json({});
    });
    const urls = await discoverCatalogUrls(opts, undefined, fetchFn as unknown as typeof fetch);
    expect(urls).toHaveLength(1);
  });
});
