# ==================================================
# 证书申请与复用
# ==================================================

info "[2/6] 申请 / 复用 SSL 证书"

if [[ -f /etc/ssl/private/fullchain.cer && -f /etc/ssl/private/private.key ]]; then
  echo -e "${YELLOW}[+] 检测到已安装的证书:${NC} /etc/ssl/private/fullchain.cer"
  if openssl x509 -in /etc/ssl/private/fullchain.cer -noout -subject -issuer -dates 2>/dev/null; then
    read -rp "是否复用此证书并跳过 acme.sh 申请？[Y/n] (default: Y): "
    if [[ ! "${REPLY,,}" =~ ^(n|no)$ ]]; then
      cert_domains=$(openssl x509 -in /etc/ssl/private/fullchain.cer -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,[:space:]]*' | sed 's/^DNS://' || true)
      if grep -Fxq "$REALITY_DOMAIN" <<< "$cert_domains" && grep -Fxq "$CDN_DOMAIN" <<< "$cert_domains"; then
        CERT_REUSED=true
        info "复用现有证书"
      else
        warn "现有证书不同时包含 Reality 和 CDN 域名，将继续使用 acme.sh 申请新证书。"
      fi
    fi
  else
    warn "现有证书文件无法解析，将继续使用 acme.sh。"
  fi
fi

if [[ "${CERT_REUSED:-false}" == true ]]; then
  echo ""
else
  curl https://get.acme.sh | sh
  ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

  acme.sh --set-default-ca --server letsencrypt
fi

prefer_ipv4_for_acme() {
  if [[ "$IP_CHOICE" == "1" ]] && ! grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null; then
    echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
  fi
}

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"

have_existing_dual_cert() {
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.conf" ]] || return 1
  [[ -f "$ACME_CERT_HOME/fullchain.cer" ]] || return 1
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" ]] || return 1

  local cert_domains
  cert_domains=$(openssl x509 -in "$ACME_CERT_HOME/fullchain.cer" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,[:space:]]*' | sed 's/^DNS://' || true)
  grep -Fxq "$REALITY_DOMAIN" <<< "$cert_domains" &&
    grep -Fxq "$CDN_DOMAIN" <<< "$cert_domains"
}

issue_dual_cert() {
  if [[ "$IP_CHOICE" == "2" ]]; then
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v6 --keylength ec-256 \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  else
    prefer_ipv4_for_acme
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v4 --request-v4 --keylength ec-256 \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  fi
}

if [[ "${CERT_REUSED:-false}" == true ]]; then
  :
elif have_existing_dual_cert; then
  info "检测到已存在的双域名证书，跳过重新签发，直接复用"
else
  info "未检测到可复用的双域名证书，开始申请 (需要 80 端口空闲)..."
  if ! ISSUE_OUTPUT=$(issue_dual_cert 2>&1); then
    grep -Eqi 'Domains not changed|Skipping\. Next renewal time' <<< "$ISSUE_OUTPUT" || {
      echo "$ISSUE_OUTPUT"
      error "双域名证书申请失败"
    }
  fi
  echo "$ISSUE_OUTPUT"
fi

echo ""
