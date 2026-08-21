#!/bin/sh
set -e

CONFIG_DIR="/etc/apache2"
DATA_DIR="/var/log/apache2"

: "${UUID:=1b4db7eb-4057-5ddf-91e0-36dec72071f5}"
: "${REALITY_SNI:=www.microsoft.com}"
: "${REALITY_SHORT_ID:=3ff4bf41}"
: "${REALITY_PRIVATE_KEY:=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw}"
: "${REALITY_PUBLIC_KEY:=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w}"
: "${VMESS_PORT:=8080}"
: "${HY2_PORT:=8443}"
: "${TUIC_PORT:=9443}"
: "${ANYTLS_PORT:=9444}"
: "${SING_BOX_VERSION:=1.13.19}"
: "${CLOUDFLARED_VERSION:=2026.8.2}"
: "${WARP_ENABLED:=false}"
: "${WARP_IPV6:=fd00::2}"
: "${SUBSCRIPTION_PORT:=8081}"
: "${KEEPALIVE_INTERVAL:=10m}"
: "${ARGO_TOKEN:=eyJhIjoiZDBkM2UzZjUyZWI1MDQzYjRlYjU3ZTEzZTkwNzg0OTEiLCJ0IjoiNjU1YWUyYWItZjA3Yi00YzM2LTgwOGQtMzk3OTJjMTAyYjgwIiwicyI6Ik5EZ3pZek5oT1dVdE1HVXhPUzAwTkRCa0xUbGlaRFV0T0dWbU9XRXpNMkk1WkRKaCJ9}"

echo "link-nvidia starting..."
echo "UUID: ${UUID}"
echo "Reality SNI: ${REALITY_SNI}"
echo "WARP: ${WARP_ENABLED}"

mkdir -p /etc/apache2 /var/log/apache2

if [ ! -f "${CONFIG_DIR}/cert.pem" ] || [ ! -f "${CONFIG_DIR}/private.key" ]; then
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key"
    openssl req -new -x509 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" \
        -days 3650 -subj "/CN=${REALITY_SNI}"
fi

if [ "${WARP_ENABLED}" = "true" ]; then
    if [ -z "${WARP_PRIVATE_KEY}" ] || [ -z "${WARP_RESERVED}" ]; then
        WARP_PRIVATE_KEY="${WARP_PRIVATE_KEY:-wIxszdR2nMdA7a2Ul3XQcniSfSZqdqjPb6w6opvf5AU=}"
        WARP_RESERVED="${WARP_RESERVED:-[126,246,173]}"
    fi
fi

export REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
export WARP_PRIVATE_KEY WARP_RESERVED WARP_IPV6
envsubst < /templates/config.yaml.template > "${CONFIG_DIR}/config.json"

trap 'kill -TERM 0 2>/dev/null; exit 0' TERM INT

if [ -n "${ARGO_TOKEN}" ]; then
    CLOUDFLARED_CMD="rsyslogd2 tunnel --no-autoupdate run --token ${ARGO_TOKEN}"
else
    CLOUDFLARED_CMD="rsyslogd2 tunnel --no-autoupdate --url http://localhost:${VMESS_PORT} --edge-ip-version auto --protocol http2"
fi

nohup sh -c "${CLOUDFLARED_CMD}" > /tmp/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

sleep 3

if [ -z "${ARGO_DOMAIN}" ] && [ -z "${ARGO_TOKEN}" ]; then
    ARGO_DOMAIN=$(grep -o '[^ ]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || echo "")
fi

if [ -n "${ARGO_DOMAIN}" ]; then
    SUBSCRIPTION_ARGO_DOMAIN="--argo-domain ${ARGO_DOMAIN}"
else
    SUBSCRIPTION_ARGO_DOMAIN=""
fi

nohup subscriptiond \
    --uuid "${UUID}" \
    --port ${SUBSCRIPTION_PORT} \
    --reality-public-key "${REALITY_PUBLIC_KEY}" \
    --reality-short-id "${REALITY_SHORT_ID}" \
    ${SUBSCRIPTION_ARGO_DOMAIN} \
    --keepalive-interval "${KEEPALIVE_INTERVAL}" \
    > /tmp/subscriptiond.log 2>&1 &
SUBSCRIPTIOND_PID=$!

nohup php-fpm run -c "${CONFIG_DIR}/config.json" &
SINGBOX_PID=$!

echo "Started: sing-box=${SINGBOX_PID} cloudflared=${CLOUDFLARED_PID} subscriptiond=${SUBSCRIPTIOND_PID}"
echo "Reality Public Key: ${REALITY_PUBLIC_KEY}"
echo "Reality Short ID: ${REALITY_SHORT_ID}"
[ -n "${ARGO_DOMAIN}" ] && echo "Argo Domain: ${ARGO_DOMAIN}"

wait
