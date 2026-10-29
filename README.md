# idp-backstage

Portal del desarrollador de la plataforma ([idp-platform](https://github.com/VictorMA97/idp-platform)),
basado en Backstage 1.56 con el frontend nuevo. Login con GitHub, catálogo de la plataforma y
PostgreSQL. Se despliega en el clúster `mgmt` por GitOps (Argo CD).

## Qué hay aquí

| Ruta | Qué |
|---|---|
| `packages/app`, `packages/backend` | La app de Backstage (frontend y backend) |
| `app-config.yaml` | Configuración base y de desarrollo local |
| `app-config.production.yaml` | Producción: todo lo sensible llega por variables de entorno |
| `catalog/` | Inventario (`entities.yaml`) y personas (`org.yaml`). Va dentro de la imagen |
| `Dockerfile` | Imagen en varias etapas, usuario no root, sin compiladores en la imagen final |
| `chart/` | Chart de Helm: Backstage + PostgreSQL + NetworkPolicies |
| `.github/workflows/ci.yaml` | Test, build, Trivy, firma Cosign, despliegue por digest |

## Autenticación

Solo GitHub. Entra quien tenga un `User` en `catalog/org.yaml` con la anotación
`github.com/user-id` igual a su `node_id` de GitHub (`gh api users/<usuario> --jq .node_id`).

`./scripts/set-owner.sh <usuario>` configura todo lo que depende de tu cuenta (descubrimiento de `svc-*`, catálogo,
plantilla) y escribe tu `node_id`. Haz commit y push después; el CI reconstruye la imagen.

## Desarrollo local

```bash
cp app-config.local.example.yaml app-config.local.yaml   # rellena la OAuth App (callback en localhost)
export GITHUB_TOKEN=...                                  # token de solo lectura
yarn install && yarn start                               # http://localhost:3000
```

## Despliegue y puesta en marcha

Los pasos completos (OAuth App, secretos, Argo CD) están en `docs/backstage.md` del repo
`idp-platform`.

## Seguridad del pipeline

Las acciones van fijadas por SHA de commit, los jobs tienen permisos mínimos y separados, la imagen
se firma de forma keyless y se despliega por digest. El pipeline es el mismo que usa, de forma opcional, la app de ejemplo `idp-sample-app`.

## Empezar de cero

`./scripts/rollback.sh` deja el repo como la plantilla: vacía `image.tag/digest` en `chart/values-mgmt.yaml` (los escribe el CI) y restaura `__GITHUB_NODE_ID__` en `catalog/org.yaml` (tu cuenta se queda; vuelve a ejecutar `set-owner.sh`). Muestra el plan y pide confirmación (`FORCE=1` para no preguntar, `DRY_RUN=1` para solo ver). No hace commit ni push, y no toca GHCR. Luego, al volver a hacer push, el CI reconstruye y vuelve a escribir tag/digest; recuerda poner de nuevo tu node_id.
