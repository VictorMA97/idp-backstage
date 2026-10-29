#!/usr/bin/env bash
# Adapta el repo a tu cuenta de GitHub: descubrimiento de servicios, catálogo, plantilla y tu usuario
# (con su node_id, que es lo que permite iniciar sesión).
# Uso: ./scripts/set-owner.sh <usuario-de-github>
#      NODE_ID=MDQ6... ./scripts/set-owner.sh <usuario>      (si no hay red hacia api.github.com)
# Idempotente. Solo edita ficheros; haz commit y push después (el CI reconstruye la imagen).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }

NEW="${1:-}"
[[ "$NEW" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] || die "Uso: ./scripts/set-owner.sh <usuario-de-github>"
NEW_LC="$(echo "$NEW" | tr '[:upper:]' '[:lower:]')"

CUR="$(awk '/^idp:/{a=1} a && /serviceDiscovery:/{b=1} b && /^[[:space:]]+owner:/{print $2; exit}' app-config.yaml)"
[[ -n "$CUR" ]] || die "No encuentro idp.serviceDiscovery.owner en app-config.yaml"
CUR_LC="$(echo "$CUR" | tr '[:upper:]' '[:lower:]')"

if [[ "$CUR" != "$NEW" ]]; then
  sed -i -E "/serviceDiscovery:/,/repositoryPattern/ s#^([[:space:]]+owner:[[:space:]]*)${CUR}#\1${NEW}#" app-config.yaml
  for f in catalog/entities.yaml catalog/optional/idp-sample-app.yaml; do
    [[ -f "$f" ]] && sed -i -E "s#\b${CUR}/#${NEW}/#g" "$f"
  done
  sed -i -E "s#^([[:space:]]+- )${CUR}[[:space:]]*\$#\1${NEW}#" catalog/templates/python-service/template.yaml
  sed -i -E "s#^([[:space:]]+name: )${CUR_LC}[[:space:]]*\$#\1${NEW_LC}#" catalog/org.yaml
  log "Cuenta cambiada: $CUR -> $NEW"
else
  log "La cuenta ya es $NEW."
fi

# node_id: identificador inmutable de GitHub; es lo que compara el login con catalog/org.yaml
NODE_ID="${NODE_ID:-}"
if [[ -z "$NODE_ID" ]]; then
  NODE_ID="$(curl -fsS "https://api.github.com/users/${NEW}" 2>/dev/null | grep '"node_id"' | cut -d'"' -f4 || true)"
fi
if [[ "$NODE_ID" =~ ^MDQ6[A-Za-z0-9+/=]+$ || "$NODE_ID" =~ ^U_[A-Za-z0-9_-]+$ ]]; then
  sed -i -E "s#(github.com/user-id:).*#\1 ${NODE_ID}#" catalog/org.yaml
  log "node_id de $NEW: $NODE_ID"
else
  warn "No pude obtener el node_id (¿límite de la API o sin red?). Repite con:"
  warn "  NODE_ID=\$(gh api users/${NEW} --jq .node_id) ./scripts/set-owner.sh ${NEW}"
  exit 1
fi
warn "Haz commit y push: git add -A && git commit -m 'chore: cuenta y node_id' && git push"
