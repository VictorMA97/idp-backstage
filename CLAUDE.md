# CLAUDE.md: idp-backstage

Backstage 1.56 (frontend nuevo, `@backstage/frontend-defaults`) para el proyecto IDP de portafolio.
Se despliega en el clúster `mgmt` (no en dev/prod) por Argo CD desde el repo `idp-platform`.

## Reglas
- Login solo con GitHub (`userIdMatchingUserEntityAnnotation`). No reintroducir el proveedor guest.
- Ningún secreto en Git: `app-config.production.yaml` solo usa `${VARIABLES}`; los valores viven en el
  Secret `backstage-secrets` de mgmt (se crea con `make backstage-secrets` en idp-platform).
- `.github/workflows/ci.yaml`: acciones fijadas por SHA (40 caracteres); no usar `pull_request_target`.
  `chart/values-mgmt.yaml` lo reescribe el CI; no editarlo a mano.
- Rama por defecto: la del repo (el CI acepta `main` y `master`).
- Los usuarios y el inventario están en `catalog/` y van dentro de la imagen: cambiarlos exige un build.

## Comandos
- `yarn install --immutable` · `yarn tsc` · `CI=true yarn test` · `yarn build:backend`
- `helm lint chart -f chart/values-mgmt.yaml --set image.tag=x`

## Estado
Compila y arranca contra PostgreSQL en pruebas locales. **La imagen y el despliegue en el clúster aún
no se han ejecutado en el entorno real.**
