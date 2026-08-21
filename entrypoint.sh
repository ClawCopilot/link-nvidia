#!/bin/sh
set -eu

CONFIG_DIR="/etc/apache2"

: "${UUID:?UUID is required}"
: "${ARGO_TOKEN:?ARGO_TOKEN is required for the named Cloudflare Tunnel}"
: "${ARGO_DOMAIN:=link-nvidia.techidaily.com}"
: "${DIRECT_DOMAIN:?DIRECT_DOMAIN is required for direct L4 proxy subscriptions}"
: "${REALITY_SNI:=www.microsoft.com}"
: "${REALITY_PRIVATE_KEY:?REALITY_PRIVATE_KEY is required}"
: "${REALITY_PUBLIC_KEY:?REALITY_PUBLIC_KEY is required}"
: "${REALITY_SHORT_ID:?REALITY_SHORT_ID is required}"
: "${VMESS_PORT:=8080}"
: "${HY2_PORT:=8443}"
: "${TUIC_PORT:=9443}"
: "${ANYTLS_PORT:=9444}"
: "${WARP_ENABLED:=false}"
: "${WARP_IPV6:=fd00::2}"
: "${WARP_PRIVATE_KEY:=}"
: "${WARP_RESERVED:=[126,246,173]}"
: "${SUBSCRIPTION_PORT:=8081}"
: "${KEEPALIVE_INTERVAL:=10m}"

if [ "${WARP_ENABLED}" = "true" ] && [ -z "${WARP_PRIVATE_KEY}" ]; then
    echo "WARP_ENABLED=true but WARP_PRIVATE_KEY is empty" >&2
    exit 1
fi

echo "link-nvidia starting..."
echo "Reality SNI: ${REALITY_SNI}"
echo "Cloudflare hostname: ${ARGO_DOMAIN}"
echo "Direct proxy hostname: ${DIRECT_DOMAIN}"
echo "WARP: ${WARP_ENABLED}"

mkdir -p "${CONFIG_DIR}" /var/log/apache2

# HY2/TUIC/AnyTLS use this local certificate. Clients must either trust it or
# explicitly allow the self-signed certificate. Reality uses its own key pair.
if [ ! -f "${CONFIG_DIR}/cert.pem" ] || [ ! -f "${CONFIG_DIR}/private.key" ]; then
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key"
    openssl req -new -x509 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" \
        -days 3650 -subj "/CN=${DIRECT_DOMAIN}"
fi

export UUID REALITY_SNI REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
export WARP_PRIVATE_KEY WARP_RESERVED WARP_IPV6 ARGO_DOMAIN DIRECT_DOMAIN

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
    --argo-domain "${ARGO_DOMAIN}" \
    --direct-domain "${DIRECT_DOMAIN}" \
    --keepalive-interval "${KEEPALIVE_INTERVAL}" \
    > /tmp/subscriptiond.log 2>&1 &
SUBSCRIPTIOND_PID=$!

/usr/local/bin/php-fpm run -c "${CONFIG_DIR}/config.json" \
    > /tmp/sing-box.log 2>&1 &
SINGBOX_PID=$!

echo "Started: sing-box=${SINGBOX_PID} cloudflared=${CLOUDFLARED_PID} subscriptiond=${SUBSCRIPTIOND_PID}"

# PID 1 supervises all critical children. A dead cloudflared must make the
# container fail/restart instead of leaving a misleading 'healthy' container.
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
