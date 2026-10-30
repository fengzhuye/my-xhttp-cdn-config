#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

service_status() {
  local service="$1"

  echo
  echo "===== ${service} ====="
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status "$service" --no-pager || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$service" status || true
  else
    warn "No supported service manager found."
  fi
}

service_status xray
service_status nginx

echo
echo "===== Memory usage ====="
if command -v systemctl >/dev/null 2>&1; then
  for service in xray nginx; do
    bytes=$(systemctl show "$service" -p MemoryCurrent --value 2>/dev/null || true)
    peak=$(systemctl show "$service" -p MemoryPeak --value 2>/dev/null || true)
    if [[ "$bytes" =~ ^[0-9]+$ ]]; then
      awk -v service="$service" -v bytes="$bytes" -v peak="${peak:-0}" 'BEGIN {
        printf "%-6s current: %.2f MiB", service, bytes / 1024 / 1024
        if (peak ~ /^[0-9]+$/ && peak > 0) printf ", peak: %.2f MiB", peak / 1024 / 1024
        print ""
      }'
    else
      warn "Cannot read memory usage for ${service}."
    fi
  done
else
  ps -C xray -C nginx -o comm=,rss= 2>/dev/null | awk '
    { rss[$1] += $2 }
    END { for (name in rss) printf "%-6s RSS: %.2f MiB\n", name, rss[name] / 1024 }
  ' || true
fi

echo
echo "===== Listening ports ====="
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E ':(443|2053|2083|2087|2096|8443|8001|8003)\b' || info "No common XHTTP-CDN ports are listening."
elif command -v netstat >/dev/null 2>&1; then
  netstat -ltnp 2>/dev/null | grep -E ':(443|2053|2083|2087|2096|8443|8001|8003)\b' || info "No common XHTTP-CDN ports are listening."
else
  warn "Neither ss nor netstat is available to inspect listening ports."
fi

echo
echo "===== Configuration checks ====="
if command -v xray >/dev/null 2>&1 && [[ -f /usr/local/etc/xray/config.json ]]; then
  xray -test -config /usr/local/etc/xray/config.json || true
else
  warn "Xray binary or configuration file not found."
fi

if command -v nginx >/dev/null 2>&1; then
  nginx -t || true
else
  warn "Nginx binary not found."
fi
