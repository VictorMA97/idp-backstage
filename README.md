# idp-backstage

Portal del desarrollador de la plataforma ([idp-platform](https://github.com/VictorMA97/idp-platform)),
basado en Backstage 1.56 con el frontend nuevo. Login con GitHub, catálogo, plantilla de servicios y
PostgreSQL. Se despliega en el clúster `mgmt` por GitOps (Argo CD).

**Cómo levantarlo dentro de la plataforma:** Etapa 5 del README de `idp-platform` y su `docs/backstage.md`.
Este README describe el código de este repo.

## Qué hay aquí

| Ruta | Qué |
|---|---|
| `packages/app`, `packages/backend` | La app de Backstage (frontend y backend) |
| `packages/app/src/polyfills.ts` | Rellena `crypto.randomUUID`, que no existe al servir por HTTP (ver Problemas conocidos) |
| `packages/backend/src/modules/serviceDiscovery.ts` | Descubre los repos `svc-*` de la cuenta y los registra en el catálogo |
| `app-config.yaml` | Configuración base y de desarrollo local |
| `app-config.production.yaml` | Producción: todo lo sensible llega por variables de entorno |
| `catalog/entities.yaml`, `catalog/org.yaml` | Inventario y personas. Van dentro de la imagen |
| `catalog/templates/python-service/` | Plantilla "Servicio Python (golden path)" |
| `Dockerfile` | Imagen en varias etapas, usuario no root, sin npm ni compiladores en la imagen final |
| `chart/` | Chart de Helm: Backstage + PostgreSQL + NetworkPolicies |
| `.github/workflows/ci.yaml` | Test, build, Trivy, firma Cosign, despliegue por digest |

## Autenticación

Solo GitHub. Entra quien tenga un `User` en `catalog/org.yaml` con la anotación `github.com/user-id`
igual a su `node_id` de GitHub:

```bash
curl -s https://api.github.com/users/<usuario> | grep node_id     # o: gh api users/<usuario> --jq .node_id
```

Si no coincide, el login falla con *unable to resolve user identity*. Para crear repos desde la plantilla,
Backstage pide además a tu cuenta los permisos `repo`, `workflow` y `public_repo` la primera vez que la uses.

## Plantilla de servicios

`catalog/templates/python-service/` genera un servicio FastAPI completo: repo en GitHub, CI con tests, Trivy,
SBOM y firma Cosign, chart de Helm y un pull request en `idp-platform` que lo registra para el despliegue.
Solo se renderizan los ficheros `.njk`; el resto (workflows, plantillas de Helm) se copia tal cual porque
también usan llaves dobles. El texto libre del usuario se inserta siempre con `| dump`. El nombre del repo
debe empezar por `svc-`: Kyverno solo admite imágenes con ese prefijo. Más en `docs/golden-path.md` de
`idp-platform`.

## Descubrimiento de servicios

Cada 5 minutos, `serviceDiscovery.ts` lista los repos públicos `svc-*` de la cuenta (`idp.serviceDiscovery`
en `app-config.yaml`) y registra los que tienen `catalog-info.yaml` en la raíz. Si un repo desaparece, su
entrada también. Si GitHub falla, el catálogo no se modifica. Se escribió en lugar de usar el módulo oficial
de GitHub porque este consulta también los repos privados y se rompe con un token que no los cubre.

## Desarrollo local

```bash
cp app-config.local.example.yaml app-config.local.yaml   # rellena la OAuth App (callback en localhost)
export GITHUB_TOKEN=...                                  # token de solo lectura
yarn install && yarn start                               # http://localhost:3000
```

Comprobaciones: `yarn tsc` · `CI=true yarn test` · `yarn workspace backend lint` · `yarn build:backend` ·
`helm lint chart -f chart/values-mgmt.yaml --set image.tag=x`.

## Despliegue

El CI construye la imagen en cada push a la rama principal (`main` o `master`), la firma y escribe tag y digest
en `chart/values-mgmt.yaml` (no lo edites a mano). La app `backstage` de Argo CD lo despliega. Los secretos
(`backstage-secrets`) no están en Git: se crean con `make backstage-secrets` en `idp-platform`.
El paquete `idp-backstage` de GHCR debe ser **público**.

## Problemas conocidos

- **`crypto.randomUUID is not a function`:** esa función solo existe en HTTPS o `localhost`; el portal se sirve
  por HTTP en `backstage.localtest.me`. `polyfills.ts` la sustituye.
- **Página en blanco tras el login:** el CSP forzaba HTTPS. En `app-config.production.yaml`,
  `backend.csp.upgrade-insecure-requests: false`.
- **Aviso `WebSocket ... /api/signals failed`:** inofensivo; el backend solo acepta WebSockets tras la primera
  petición HTTP y el cliente reintenta.
- **`ENOTFOUND backstage-postgres` al arrancar:** el chart espera a PostgreSQL con un initContainer.
- **Crear el repo desde la plantilla da 404:** el token de usuario solo tiene `read:user`. Revoca la app en
  github.com/settings/applications, cierra sesión y vuelve a entrar para repetir el consentimiento.

## Seguridad del pipeline

Las acciones van fijadas por SHA de commit, los jobs tienen permisos mínimos y separados, la imagen se firma
de forma keyless y se despliega por digest. Kyverno verifica esa firma en mgmt. Detalles en el README de
`idp-sample-app`.
