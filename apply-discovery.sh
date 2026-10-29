#!/usr/bin/env bash
# Activa el descubrimiento automático de repos svc-* en idp-backstage (versión propia, sin el módulo oficial).
# Edita app-config.yaml, packages/backend/src/index.ts y la plantilla python-service; ajusta dependencias con yarn.
# Funciona tanto sobre tu repo original como si ya aplicaste la versión anterior (con el módulo oficial).
# Idempotente. Uso, desde la raíz de idp-backstage (con los ficheros del zip ya copiados):
#   ./apply-discovery.sh [--skip-install]
set -euo pipefail
command -v python3 >/dev/null || { echo "[x] Falta python3" >&2; exit 1; }
[[ -f app-config.yaml && -f packages/backend/src/index.ts ]] \
  || { echo "[x] Ejecútalo desde la raíz de idp-backstage" >&2; exit 1; }
[[ -f packages/backend/src/modules/serviceDiscovery.ts ]] \
  || { echo "[x] Falta packages/backend/src/modules/serviceDiscovery.ts: copia antes el contenido del zip" >&2; exit 1; }

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
out_old = """      - title: Abrir en el catálogo
        icon: catalog
        entityRef: ${{ steps['register'].output.entityRef }}
"""
steps_old = "          1. Espera a que el workflow **ci**"
steps_new = "          0. El servicio aparecerá solo en el catálogo en unos 5 minutos (descubrimiento automático de repos `svc-*`).\n" + steps_old
v1_start = "\n  # Descubrimiento automático: todos los repos svc-* de la cuenta"
idp_block = """
# Descubrimiento automático de servicios: todos los repos públicos svc-* de la cuenta que tengan
# catalog-info.yaml en la raíz se registran solos y desaparecen si se borran. Es la fuente de verdad:
# el catálogo se reconstruye aunque se pierda la base de datos. Usa el token de integrations.github
# (solo lectura de repos públicos). Código: packages/backend/src/modules/serviceDiscovery.ts
idp:
  serviceDiscovery:
    owner: VictorMA97
    repositoryPattern: '^svc-[a-z0-9-]+$'
    schedule:
      frequency: { minutes: 5 }
      timeout: { minutes: 3 }
"""
v1_idx = "// Descubre los repos svc-* de la cuenta (ver catalog.providers.github en app-config.yaml)\nbackend.add(import('@backstage/plugin-catalog-backend-module-github'));\n"
new_idx = "// Descubre los repos svc-* de la cuenta (ver idp.serviceDiscovery en app-config.yaml)\nbackend.add(import('./modules/serviceDiscovery'));\n"
anchor = "  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),\n);\n"

def read(p):
    try: return open(p,encoding='utf-8').read()
    except FileNotFoundError: sys.exit(f"[x] No existe {p}")
cfg, idx, tpl = read(CFG), read(IDX), read(TPL)
msgs=[]
# --- app-config: quitar el bloque de la versión anterior y poner el nuevo
if v1_start in cfg:
    i=cfg.index(v1_start); j=cfg.index("\nkubernetes:", i)
    cfg=cfg[:i]+"\n"+cfg[j+1:]; msgs.append(f"{CFG}: quitado el proveedor oficial (versión anterior)")
if "\nidp:\n  serviceDiscovery:" in cfg: msgs.append(f"{CFG}: idp.serviceDiscovery ya estaba")
else: cfg=cfg.rstrip('\n')+'\n'+idp_block; msgs.append(f"{CFG}: añadido idp.serviceDiscovery")
# --- index.ts
if "import('./modules/serviceDiscovery')" in idx: msgs.append(f"{IDX}: ya estaba")
elif v1_idx in idx: idx=idx.replace(v1_idx,new_idx,1); msgs.append(f"{IDX}: sustituido el módulo oficial por el propio")
elif idx.count(anchor)==1: idx=idx.replace(anchor,anchor+new_idx,1); msgs.append(f"{IDX}: añadido el módulo")
else: sys.exit(f"[x] {IDX}: no encuentro dónde insertar el módulo")
# --- plantilla
if tpl_register in tpl:
    tpl=tpl.replace(tpl_register,"",1).replace(out_old,"",1); msgs.append(f"{TPL}: quitado el registro manual")
else: msgs.append(f"{TPL}: ya estaba")
if steps_new not in tpl and steps_old in tpl: tpl=tpl.replace(steps_old,steps_new,1)
for p,t in ((CFG,cfg),(IDX,idx),(TPL,tpl)): open(p,'w',encoding='utf-8').write(t)
print(*msgs,sep="\n")
PY

if [[ "${1:-}" != "--skip-install" ]]; then
  command -v yarn >/dev/null || { echo "[x] Falta yarn" >&2; exit 1; }
  if grep -q 'plugin-catalog-backend-module-github' packages/backend/package.json; then
    yarn workspace backend remove @backstage/plugin-catalog-backend-module-github
  fi
  yarn workspace backend add @backstage/backend-plugin-api @backstage/plugin-catalog-node @backstage/integration
fi
echo "Hecho. Siguiente: yarn tsc, CI=true yarn test, commit y push (el CI reconstruye la imagen)."
