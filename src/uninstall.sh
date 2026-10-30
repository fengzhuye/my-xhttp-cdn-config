#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Please run this script as root."

read -rp "This removes Xray, the XHTTP-CDN Nginx configuration, certificates installed by this script, and generated client files. Continue? [y/N]: "
[[ "${REPLY,,}" == "y" ]] || { info "Cancelled."; exit 0; }

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now xray nginx 2>/dev/null || true
elif command -v rc-service >/dev/null 2>&1; then
  rc-service xray stop 2>/dev/null || true
  rc-service nginx stop 2>/dev/null || true
  command -v rc-update >/dev/null 2>&1 && rc-update del xray default 2>/dev/null || true
  command -v rc-update >/dev/null 2>&1 && rc-update del nginx default 2>/dev/null || true
fi

rm -f /etc/systemd/system/xray.service /usr/lib/systemd/system/xray.service
rm -f /etc/init.d/xray
rm -f /usr/local/bin/xray
rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray
rm -rf /etc/xhttp-cdn

# Keep certificates and acme.sh data by default so a later installation can reuse them.
# This project installs Nginx from source and owns these paths.
rm -f /etc/nginx/nginx.conf
rm -f /etc/systemd/system/nginx.service /usr/lib/systemd/system/nginx.service
rm -f /etc/init.d/nginx
rm -f /usr/sbin/nginx
rm -rf /usr/local/nginx
rm -f /run/nginx.pid

rm -rf /var/www/dist

for home in /root /home/*; do
  [[ -d "$home" ]] || continue
  rm -rf "$home/xhttp-cdn-config"
  # Remove output files written by installer versions before xhttp-cdn-config/ was introduced.
  rm -f "$home/client-config.txt" \
        "$home/client-config-mihomo-full.yaml" \
        "$home/client-config-mihomo-nodes.yaml" \
        "$home/subscription-links.txt" \
        "$home"/subscription-*.png
done

  read -rp "是否同时删除 acme.sh 数据和证书？这会删除 root 的 acme.sh 管理的所有证书，且无法恢复。[y/N] (default: N): "
if [[ "${REPLY,,}" == "y" ]]; then
  if [[ -x /root/.acme.sh/acme.sh ]]; then
    /root/.acme.sh/acme.sh --uninstall || warn "acme.sh uninstall command failed; removing its files anyway."
  fi
  rm -rf /root/.acme.sh
  rm -f /usr/local/bin/acme.sh
  rm -f /etc/ssl/private/private.key /etc/ssl/private/fullchain.cer
  sed -i '\|^precedence ::ffff:0:0/96  100$|d' /etc/gai.conf 2>/dev/null || true
  if crontab -l >/dev/null 2>&1; then
    crontab -l | grep -vE '(^|[[:space:]])[^#]*\.acme\.sh/acme\.sh[[:space:]]+--cron' | crontab -
  fi
  info "acme.sh data, project-installed certificate files, and the ACME IPv4 preference were removed."
  if crontab -l 2>/dev/null | grep -Eqi 'acme\.sh|certbot|lego'; then
    warn "Remaining certificate-related root cron entries:"
    crontab -l 2>/dev/null | grep -Ei 'acme\.sh|certbot|lego' || true
  else
    info "No certificate-related root cron entries remain."
  fi
else
  info "Kept acme.sh data and certificates for reuse by a future installation."
fi

  read -rp "是否同时删除本项目可选安装的构建/运行软件包？可能影响其他应用。[y/N] (default: N): "
if [[ "${REPLY,,}" == "y" ]]; then
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
  else
    ID=""
  fi
  case "$ID" in
    debian|ubuntu)
      apt purge -y gcc g++ make libpcre3-dev libpcre2-dev zlib1g-dev libssl-dev libcrypt-dev qrencode socat || true
      apt autoremove --purge -y || true
      apt clean || true
      ;;
    alpine)
      apk del build-base linux-headers pcre2-dev zlib-dev openssl-dev libqrencode-tools socat 2>/dev/null || true
      ;;
    *)
      warn "Automatic package cleanup is currently provided only for Debian/Ubuntu and Alpine. Remove packages manually on this distribution."
      ;;
  esac
else
  info "Kept installed packages."
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
fi

info "XHTTP-CDN Xray and Nginx configuration removed."

remaining_units=()
if command -v systemctl >/dev/null 2>&1; then
  while IFS= read -r unit; do
    [[ -n "$unit" ]] && remaining_units+=("$unit")
  done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '$1 ~ /(xray|nginx|acme|certbot|lego)/ { print $1 }')
fi

if ((${#remaining_units[@]})); then
  warn "Remaining related systemd service units:"
  printf '  %s\n' "${remaining_units[@]}"
else
  info "No remaining related systemd service units were found."
fi

if [[ -d /root/.acme.sh ]]; then
  warn "acme.sh account and certificate data remains: /root/.acme.sh"
fi

cat <<'CLEANUP'

Useful inspection commands:

  # Inspect remaining related systemd units and processes:
  systemctl list-unit-files --type=service | grep -Ei 'xray|nginx|acme|certbot|lego'
  ps -ef | grep -Ei '[x]ray|[n]ginx|[a]cme|[c]ertbot|[l]ego'

  # Check whether firewall rules still allow the old public ports:
  ufw status numbered
  firewall-cmd --list-ports
CLEANUP

warn "Packages and acme.sh data were kept unless you explicitly chose to remove them."
