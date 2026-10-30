#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT_DIR"
bash .github/scripts/build-install.sh

echo
printf 'Build complete. Run one of:\n'
printf '  # Standard installer: Xray, Nginx, ACME certificates, and the four base nodes.\n'
printf '  bash %s/dist/install.sh\n' "$ROOT_DIR"
printf '  # Xpadding installer: standard installer plus XHTTP xpadding and optional CDN ECH settings.\n'
printf '  bash %s/dist/install-xpadding.sh\n' "$ROOT_DIR"
printf '  # Remove the XHTTP-CDN deployment.\n'
printf '  bash %s/dist/uninstall.sh\n' "$ROOT_DIR"
