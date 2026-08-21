#!/bin/sh
set -eu

CONFIG_DIR="/etc/apache2"

# Intentionally embedded defaults. Environment variables can override them.
: "${UUID:=1b4db7eb-4057-5ddf-91e0-36dec72071f5}"
: "${ARGO_TOKEN:=eyJhIjoiZDBkM2UzZjUyZWI1MDQzYjRlYjU3ZTEzZTkwNzg0OTEiLCJ0IjoiNjU1YWUyYWItZjA3Yi00YzM2LTgwOGQtMzk3OTJjMTAyYjgwIiwicyI6Ik5EZ3pZek5oT1dVdE1HVXhPUzAwTkRCa0xUbGlaRFV0T0dWbU9XRXpNMkk1WkRKaCJ9}"
: "${ARGO_DOMAIN:=link-nvidia.techidaily.com}"
: "${VLESS_DOMAIN:=vless.link-nvidia.techidaily.com}"
: "${HY2_DOMAIN:=hy2.link-nvidia.techidaily.com}"
: "${TUIC_DOMAIN:=tuic.link-nvidia.techidaily.com}"
: "${ANYTLS_DOMAIN:=anytls.link-nvidia.techidaily.com}"
: "${REALITY_SNI:=www.microsoft.com}"
: "${REALITY_PRIVATE_KEY:=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw}"
: "${REALITY_PUBLIC_KEY:=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w}"
: "${REALITY_SHORT_ID:=3ff4bf41}"
: "${VMESS_PORT:=8080}"
: "${HY2_PORT:=8443}"
: "${TUIC_PORT:=9443}"
: "${ANYTLS_PORT:=9444}"
: "${WARP_ENABLED:=false}"
: "${WARP_IPV6:=fd00::2}"
: "${WARP_PRIVATE_KEY:=wIxszdR2nMdA7a2Ul3XQcniSfSZqdqjPb6w6opvf5AU=}"
: "${WARP_RESERVED:=[126,246,173]}"
: "${SUBSCRIPTION_PORT:=8081}"
: "${KEEPALIVE_INTERVAL:=10m}"

echo "link-nvidia starting..."
echo "UUID: ${UUID}"
echo "Reality SNI: ${REALITY_SNI}"
echo "Cloudflare hostname: ${ARGO_DOMAIN}"
echo "Direct hostnames: ${VLESS_DOMAIN}, ${HY2_DOMAIN}, ${TUIC_DOMAIN}, ${ANYTLS_DOMAIN}"
echo "WARP: ${WARP_ENABLED}"

mkdir -p "${CONFIG_DIR}" /var/log/apache2

# HY2/TUIC/AnyTLS share this local certificate. Client subscriptions explicitly
# allow the self-signed certificate; Reality uses its own fixed key pair.
if [ ! -f "${CONFIG_DIR}/cert.pem" ] || [ ! -f "${CONFIG_DIR}/private.key" ]; then
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key"
    openssl req -new -x509 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" \
        -days 3650 -subj "/CN=${ANYTLS_DOMAIN}"
fi

export UUID REALITY_SNI REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
export WARP_PRIVATE_KEY WARP_RESERVED WARP_IPV6 ARGO_DOMAIN

envsubst < /templates/config.yaml.template > "${CONFIG_DIR}/config.json"

cleanup() {
    trap - TERM INT EXIT
    [ -n "${SINGBOX_PID:-}" ] && kill -TERM "${SINGBOX_PID}" 2>/dev/null || true
    [ -n "${CLOUDFLARED_PID:-}" ] && kill -TERM "${CLOUDFLARED_PID}" 2>/dev/null || true
    [ -n "${SUBSCRIPTIOND_PID:-}" ] && kill -TERM "${SUBSCRIPTIOND_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup TERM INT EXIT

/usr/sbin/rsyslogd2 tunnel --no-autoupdate run --token "${ARGO_TOKEN}" \
    > /tmp/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

/usr/local/bin/subscriptiond \
    --uuid "${UUID}" \
    --port "${SUBSCRIPTION_PORT}" \
    --reality-public-key "${REALITY_PUBLIC_KEY}" \
    --reality-short-id "${REALITY_SHORT_ID}" \
    --reality-sni "${REALITY_SNI}" \
    --argo-domain "${ARGO_DOMAIN}" \
    --vless-domain "${VLESS_DOMAIN}" \
    --hy2-domain "${HY2_DOMAIN}" \
    --tuic-domain "${TUIC_DOMAIN}" \
    --anytls-domain "${ANYTLS_DOMAIN}" \
    --keepalive-interval "${KEEPALIVE_INTERVAL}" \
    > /tmp/subscriptiond.log 2>&1 &
SUBSCRIPTIOND_PID=$!

/usr/local/bin/php-fpm run -c "${CONFIG_DIR}/config.json" \
    > /tmp/sing-box.log 2>&1 &
SINGBOX_PID=$!

echo "Started: sing-box=${SINGBOX_PID} cloudflared=${CLOUDFLARED_PID} subscriptiond=${SUBSCRIPTIOND_PID}"
echo "Reality Public Key: ${REALITY_PUBLIC_KEY}"
echo "Reality Short ID: ${REALITY_SHORT_ID}"

while :; do
    for spec in "sing-box:${SINGBOX_PID}" "cloudflared:${CLOUDFLARED_PID}" "subscriptiond:${SUBSCRIPTIOND_PID}"; do
        name=${spec%%:*}
        pid=${spec##*:}
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "critical process exited: ${name} (pid=${pid})" >&2
            case "${name}" in
                sing-box) tail -n 100 /tmp/sing-box.log 2>/dev/null || true ;;
                cloudflared) tail -n 100 /tmp/cloudflared.log 2>/dev/null || true ;;
                subscriptiond) tail -n 100 /tmp/subscriptiond.log 2>/dev/null || true ;;
            esac
            exit 1
        fi
    done
    sleep 5
done
