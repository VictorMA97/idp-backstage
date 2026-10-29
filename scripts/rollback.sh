#!/usr/bin/env bash
# Deja idp-backstage como en la plantilla: quita lo que el setup o el CI escribieron en git.
# No hace commit ni push; no toca GHCR ni GitHub. Variables: FORCE=1 (sin preguntar), DRY_RUN=1 (solo muestra).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -d .git ] || { echo "Ejecútalo dentro del repo idp-backstage: ./scripts/rollback.sh"; exit 1; }

VALUES=(chart/values-mgmt.yaml)
BASE=$'image:\n  tag: ""\n  digest: ""'
todo=()

for f in "${VALUES[@]}"; do
  [ -f "$f" ] || continue
  { awk '/^image:/{exit} {print}' "$f"; printf '%s\n' "$BASE"; } | cmp -s - "$f" || todo+=("values:$f")
done
if [ -f catalog/org.yaml ] && grep -qE 'github.com/user-id: *[^ _#]' catalog/org.yaml; then todo+=("nodeid:catalog/org.yaml"); fi

if [ ${#todo[@]} -eq 0 ]; then echo "Nada que revertir: idp-backstage ya está como la plantilla."; exit 0; fi

echo "Se revertirá:"
for t in "${todo[@]}"; do echo "  - ${t#*:}"; done
[ "${DRY_RUN:-0}" = 1 ] && { echo "(DRY_RUN: no se ha cambiado nada)"; exit 0; }
if [ "${FORCE:-0}" != 1 ]; then
  read -r -p "¿Continuar? [y/N] " a; [[ "$a" =~ ^[yYsS]$ ]] || { echo "Cancelado."; exit 1; }
fi

for t in "${todo[@]}"; do
  case "$t" in
    values:*) f="${t#values:}"; { awk '/^image:/{exit} {print}' "$f"; printf '%s\n' "$BASE"; } > "$f.tmp" && mv "$f.tmp" "$f" ;;
    nodeid:*) sed -i -E 's|(github.com/user-id:) *[^ #]+|\1 __GITHUB_NODE_ID__|' catalog/org.yaml ;;
  esac
done
echo
echo "Hecho. Para subirlo a git:"
echo "  git add -A && git commit -m 'chore: volver a la plantilla' && git push"
echo "Nota: el push a main/master dispara el CI y volverá a escribir tag/digest."
