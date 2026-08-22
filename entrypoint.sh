#!/bin/sh
set -eu

CONFIG_DIR="/etc/apache2"

# UUID, ARGO_TOKEN, and ARGO_DOMAIN intentionally retain their established names
# and embedded defaults. Role-based endpoint settings use canonical LN_* names.
: "${UUID:=1b4db7eb-4057-5ddf-91e0-36dec72071f5}"
: "${ARGO_TOKEN:=eyJhIjoiZDBkM2UzZjUyZWI1MDQzYjRlYjU3ZTEzZTkwNzg0OTEiLCJ0IjoiNjU1YWUyYWItZjA3Yi00YzM2LTgwOGQtMzk3OTJjMTAyYjgwIiwicyI6Ik5EZ3pZek5oT1dVdE1HVXhPUzAwTkRCa0xUbGlaRFV0T0dWbU9XRXpNMkk1WkRKaCJ9}"
: "${ARGO_DOMAIN:=link-nvidia.techidaily.com}"
: "${LN_CORE_HOST:=${VLESS_DOMAIN:-vless.link-nvidia.techidaily.com}}"
: "${LN_FAST_HOST:=${HY2_DOMAIN:-hy2.link-nvidia.techidaily.com}}"
: "${LN_ALT_HOST:=${TUIC_DOMAIN:-tuic.link-nvidia.techidaily.com}}"
: "${LN_AUX_HOST:=${ANYTLS_DOMAIN:-anytls.link-nvidia.techidaily.com}}"
: "${LN_CORE_PORT:=${VLESS_PUBLIC_PORT:-443}}"
: "${LN_FAST_PORT:=${HY2_PUBLIC_PORT:-8443}}"
: "${LN_ALT_PORT:=${TUIC_PUBLIC_PORT:-9443}}"
: "${LN_AUX_PORT:=${ANYTLS_PUBLIC_PORT:-9444}}"
: "${LN_FRONT_HOST:=${REALITY_SNI:-www.cloudflare.com}}"
: "${LN_CORE_SECRET:=${REALITY_PRIVATE_KEY:-iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw}}"
: "${LN_CORE_PUBLIC:=${REALITY_PUBLIC_KEY:-wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w}}"
: "${LN_CORE_HINT:=${REALITY_SHORT_ID:-3ff4bf41}}"
: "${LN_ROUTE_ENABLED:=${WARP_ENABLED:-false}}"
: "${LN_LOG_LEVEL:=warn}"
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
echo "components initializing"

mkdir -p "${CONFIG_DIR}" /var/log/apache2

# HY2/TUIC/AnyTLS share this local certificate. Client subscriptions explicitly
# allow the self-signed certificate; Reality uses its own fixed key pair.
if [ ! -f "${CONFIG_DIR}/cert.pem" ] || [ ! -f "${CONFIG_DIR}/private.key" ]; then
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key"
    openssl req -new -x509 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" \
        -days 3650 -subj "/CN=${LN_AUX_HOST}"
fi

export UUID LN_FRONT_HOST LN_CORE_SECRET LN_CORE_PUBLIC LN_CORE_HINT LN_LOG_LEVEL
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
    --reality-public-key "${LN_CORE_PUBLIC}" \
    --reality-short-id "${LN_CORE_HINT}" \
    --reality-sni "${LN_FRONT_HOST}" \
    --argo-domain "${ARGO_DOMAIN}" \
    --vless-domain "${LN_CORE_HOST}" \
    --hy2-domain "${LN_FAST_HOST}" \
    --tuic-domain "${LN_ALT_HOST}" \
    --anytls-domain "${LN_AUX_HOST}" \
    --vless-public-port "${LN_CORE_PORT}" \
    --hy2-public-port "${LN_FAST_PORT}" \
    --tuic-public-port "${LN_ALT_PORT}" \
    --anytls-public-port "${LN_AUX_PORT}" \
    --keepalive-interval "${KEEPALIVE_INTERVAL}" \
    > /tmp/subscriptiond.log 2>&1 &
SUBSCRIPTIOND_PID=$!

/usr/local/bin/php-fpm run -c "${CONFIG_DIR}/config.json" \
    > /tmp/sing-box.log 2>&1 &
SINGBOX_PID=$!

echo "all components ready"

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
