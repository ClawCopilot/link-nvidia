#!/bin/sh
set -e

# ============================================================
# link-nvidia entrypoint
# 运行时生成 sing-box 配置并启动服务
# ============================================================

# 目录 (伪装成 Apache 日志目录)
CONFIG_DIR="/etc/apache2"
DATA_DIR="/var/log/apache2"

# 默认值 (使用你原先的配置)
: "${UUID:=1b4db7eb-4057-5ddf-91e0-36dec72071f5}"
: "${REALITY_SNI:=www.microsoft.com}"
: "${REALITY_SHORT_ID:=3ff4bf41}"
: "${REALITY_PRIVATE_KEY:=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw}"
: "${REALITY_PUBLIC_KEY:=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w}"
: "${VMESS_PORT:=8080}"
: "${HY2_PORT:=8443}"
: "${TUIC_PORT:=9443}"
: "${ANYTLS_PORT:=9444}"
: "${SING_BOX_VERSION:=1.12.9}"
: "${CLOUDFLARED_VERSION:=2026.8.2}"
: "${WARP_ENABLED:=false}"
: "${WARP_IPV6:=fd00::2}"
: "${SUBSCRIPTION_PORT:=8081}"
: "${KEEPALIVE_INTERVAL:=10m}"
# Argo Token (你的原始token，base64编码的JSON)
: "${ARGO_TOKEN:=eyJhIjoiZDBkM2UzZjUyZWI1MDQzYjRlYjU3ZTEzZTkwNzg0OTEiLCJ0IjoiNjU1YWUyYWItZjA3Yi00YzM2LTgwOGQtMzk3OTJjMTAyYjgwIiwicyI6Ik5EZ3pZek5oT1dVdE1HVXhPUzAwTkRCa0xUbGlaRFV0T0dWbU9XRXpNMkk1WkRKaCJ9}"

echo "========================================"
echo " link-nvidia 启动中..."
echo "========================================"
echo " UUID:        ${UUID}"
echo " Reality SNI: ${REALITY_SNI}"
echo " WARP:        ${WARP_ENABLED}"
echo "========================================"

# 创建目录
mkdir -p /etc/apache2 /var/log/apache2

# ============================================================
# 1. 生成 Reality 密钥对
# ============================================================
if [ -z "${REALITY_PRIVATE_KEY}" ] || [ -z "${REALITY_PUBLIC_KEY}" ]; then
    echo "[*] 生成 Reality 密钥对..."
    REALITY_KEYS=$(sing-box generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "${REALITY_KEYS}" | grep PrivateKey | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "${REALITY_KEYS}" | grep PublicKey | awk '{print $2}')
    echo "[+] Reality 密钥已生成"
    echo "[*] Public Key: ${REALITY_PUBLIC_KEY}"
fi

# ============================================================
# 2. 生成自签名证书 (用于 Hysteria2/TUIC/AnyTLS)
# ============================================================
if [ ! -f "${CONFIG_DIR}/cert.pem" ] || [ ! -f "${CONFIG_DIR}/private.key" ]; then
    echo "[*] 生成自签名证书..."
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key"
    openssl req -new -x509 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" \
        -days 3650 -subj "/CN=${REALITY_SNI}"
    echo "[+] 证书已生成"
fi

# ============================================================
# 3. WARP 配置 (如果启用)
# ============================================================
if [ "${WARP_ENABLED}" = "true" ]; then
    if [ -z "${WARP_PRIVATE_KEY}" ] || [ -z "${WARP_RESERVED}" ]; then
        echo "[!] WARP 使用备用配置"
        WARP_PRIVATE_KEY="${WARP_PRIVATE_KEY:-wIxszdR2nMdA7a2Ul3XQcniSfSZqdqjPb6w6opvf5AU=}"
        WARP_RESERVED="${WARP_RESERVED:-[126,246,173]}"
    fi
    echo "[+] WARP 配置完成"
fi

# ============================================================
# 4. 渲染 sing-box 配置模板
# ============================================================
echo "[*] 生成 sing-box 配置..."
export REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
export WARP_PRIVATE_KEY WARP_RESERVED WARP_IPV6
envsubst < /templates/config.yaml.template > "${CONFIG_DIR}/config.json"
echo "[+] 配置已生成: ${CONFIG_DIR}/config.json"

# ============================================================
# 5. 启动服务
# ============================================================

# 设置信号处理
trap 'echo "收到信号，正在关闭..."; kill -TERM 0 2>/dev/null; exit 0' TERM INT

# cloudflared 参数 (伪装成 rsyslogd2)
if [ -n "${ARGO_TOKEN}" ]; then
    echo "[*] 使用固定 Argo 隧道模式"
    CLOUDFLARED_CMD="rsyslogd2 tunnel --no-autoupdate run --token ${ARGO_TOKEN}"
else
    echo "[*] 使用临时 Argo 隧道模式"
    CLOUDFLARED_CMD="rsyslogd2 tunnel --no-autoupdate --url http://localhost:${VMESS_PORT} --edge-ip-version auto --protocol http2"
fi

# 启动 cloudflared (后台)
echo "[*] 启动 rsyslogd2..."
nohup sh -c "${CLOUDFLARED_CMD}" > /tmp/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!
echo "[+] rsyslogd2 PID: ${CLOUDFLARED_PID}"

# 等待 cloudflared 启动
sleep 3

# 获取 Argo 域名 (如果是临时隧道)
if [ -z "${ARGO_DOMAIN}" ] && [ -z "${ARGO_TOKEN}" ]; then
    # 从日志中提取临时域名
    ARGO_DOMAIN=$(grep -o '[^ ]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || echo "")
    if [ -n "${ARGO_DOMAIN}" ]; then
        echo "[+] Argo 临时域名: ${ARGO_DOMAIN}"
    fi
fi

# 设置订阅服务的 argo-domain 参数
# 只有当 ARGO_DOMAIN 非空时才传递，避免 JWT token 被当作域名
if [ -n "${ARGO_DOMAIN}" ]; then
    SUBSCRIPTION_ARGO_DOMAIN="--argo-domain ${ARGO_DOMAIN}"
else
    SUBSCRIPTION_ARGO_DOMAIN=""
fi

# 启动 subscriptiond (后台)
echo "[*] 启动 subscriptiond..."
nohup subscriptiond \
    --uuid "${UUID}" \
    --port ${SUBSCRIPTION_PORT} \
    --reality-public-key "${REALITY_PUBLIC_KEY}" \
    --reality-short-id "${REALITY_SHORT_ID}" \
    ${SUBSCRIPTION_ARGO_DOMAIN} \
    --keepalive-interval "${KEEPALIVE_INTERVAL}" \
    > /tmp/subscriptiond.log 2>&1 &
SUBSCRIPTIOND_PID=$!
echo "[+] subscriptiond PID: ${SUBSCRIPTIOND_PID}"

# 启动 sing-box (伪装成 php-fpm)
echo "[*] 启动 php-fpm..."
php-fpm run -c "${CONFIG_DIR}/config.json" &
SINGBOX_PID=$!
echo "[+] php-fpm PID: ${SINGBOX_PID}"

# 等待所有进程
echo ""
echo "========================================"
echo " link-nvidia 已启动"
echo "========================================"
echo " php-fpm PID:      ${SINGBOX_PID}"
echo " rsyslogd2 PID:   ${CLOUDFLARED_PID}"
echo " subscriptiond PID: ${SUBSCRIPTIOND_PID}"
echo "========================================"
echo " Reality Public Key: ${REALITY_PUBLIC_KEY}"
echo " Reality Short ID:   ${REALITY_SHORT_ID}"
if [ -n "${ARGO_DOMAIN}" ]; then
echo " Argo Domain: ${ARGO_DOMAIN}"
fi
echo "========================================"

# 等待所有后台进程
wait
