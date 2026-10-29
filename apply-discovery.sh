#!/usr/bin/env bash
# Activa el descubrimiento automático de repos svc-* en idp-backstage.
# Edita app-config.yaml, packages/backend/src/index.ts y la plantilla python-service, e instala el
# módulo con yarn (así yarn.lock se actualiza sobre TU copia, sin pisar nada). Idempotente.
# Uso, desde la raíz de idp-backstage:   ./apply-discovery.sh [--skip-install]
set -euo pipefail
command -v python3 >/dev/null || { echo "[x] Falta python3" >&2; exit 1; }
[[ -f app-config.yaml && -f packages/backend/src/index.ts ]] \
  || { echo "[x] Ejecútalo desde la raíz de idp-backstage" >&2; exit 1; }

python3 - <<'PY'
import sys
CFG='app-config.yaml'; IDX='packages/backend/src/index.ts'; TPL='catalog/templates/python-service/template.yaml'
tpl_register = """    - id: register
      name: Registrar el componente en el catálogo
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps['publish'].output.repoContentsUrl }}
        catalogInfoPath: '/catalog-info.yaml'

"""
loc = """    - type: file
      target: ../../catalog/templates/python-service/template.yaml
      rules:
        - allow: [Template]
"""
providers = """
  # Descubrimiento automático: todos los repos svc-* de la cuenta que tengan catalog-info.yaml en la raíz
  # se registran solos (y desaparecen si se borran). Es la fuente de verdad: así el catálogo se reconstruye
  # aunque se pierda la base de datos. Usa el token de integrations.github (solo lectura).
  providers:
    github:
      servicios:
        organization: VictorMA97   # también vale para cuentas personales
        catalogPath: /catalog-info.yaml
        validateLocationsExist: true
        filters:
          repository: '^svc-[a-z0-9-]+$'
          visibility: [public]
        schedule:
          frequency: { minutes: 5 }
          timeout: { minutes: 3 }
"""
anchor = "  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),\n);\n"
idx_add = "// Descubre los repos svc-* de la cuenta (ver catalog.providers.github en app-config.yaml)\nbackend.add(import('@backstage/plugin-catalog-backend-module-github'));\n"
out_old = """      - title: Abrir en el catálogo
        icon: catalog
        entityRef: ${{ steps['register'].output.entityRef }}
"""
steps_note_old = "          1. Espera a que el workflow **ci**"
steps_note_new = "          0. El servicio aparecerá solo en el catálogo en unos 5 minutos (descubrimiento automático de repos `svc-*`).\n" + steps_note_old

def read(p):
    try: return open(p,encoding='utf-8').read()
    except FileNotFoundError: sys.exit(f"[x] No existe {p}")
cfg, idx, tpl = read(CFG), read(IDX), read(TPL)
msgs=[]
# app-config
if 'github-provider' in cfg or '      servicios:' in cfg: msgs.append(f"{CFG}: ya estaba")
elif cfg.count(loc)!=1: sys.exit(f"[x] {CFG}: no encuentro el bloque de la plantilla en catalog.locations (¿lo has cambiado?)")
else: cfg=cfg.replace(loc,loc+providers,1); msgs.append(f"{CFG}: añadido catalog.providers.github")
# index.ts
if 'plugin-catalog-backend-module-github' in idx: msgs.append(f"{IDX}: ya estaba")
elif idx.count(anchor)!=1: sys.exit(f"[x] {IDX}: no encuentro el punto de inserción")
else: idx=idx.replace(anchor,anchor+idx_add,1); msgs.append(f"{IDX}: añadido el módulo")
# plantilla
if tpl_register in tpl:
    tpl=tpl.replace(tpl_register,"",1)
    tpl=tpl.replace(out_old,"",1)
    msgs.append(f"{TPL}: quitado el registro manual (lo hace el descubrimiento)")
else: msgs.append(f"{TPL}: ya estaba")
if steps_note_new not in tpl and steps_note_old in tpl: tpl=tpl.replace(steps_note_old,steps_note_new,1)
for p,t in ((CFG,cfg),(IDX,idx),(TPL,tpl)): open(p,'w',encoding='utf-8').write(t)
print(*msgs,sep="\n")
PY

if [[ "${1:-}" != "--skip-install" ]]; then
  command -v yarn >/dev/null || { echo "[x] Falta yarn" >&2; exit 1; }
  yarn workspace backend add @backstage/plugin-catalog-backend-module-github
fi
echo "Hecho. Siguiente: yarn tsc, commit y push (el CI reconstruye la imagen)."
