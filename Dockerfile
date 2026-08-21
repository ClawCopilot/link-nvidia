FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /build
COPY subscriptiond/ .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o subscriptiond .

FROM alpine:3.20
ARG SING_BOX_VERSION=1.13.19
ARG CLOUDFLARED_VERSION=2026.8.2

LABEL org.opencontainers.image.title="link-nvidia"
LABEL org.opencontainers.image.description="sing-box multi-protocol proxy with Cloudflare Tunnel"
LABEL org.opencontainers.image.source="https://github.com/ClawCopilot/link-nvidia"

RUN apk add --no-cache \
    ca-certificates openssl wget curl bash tzdata jq gettext \
    && rm -rf /var/cache/apk/*

WORKDIR /app

RUN ARCH=$(case $(uname -m) in x86_64) echo "amd64" ;; aarch64) echo "arm64" ;; *) echo "amd64" ;; esac) && \
    wget -q "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz" -O /tmp/sing-box.tar.gz && \
    tar -zxf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/php-fpm && \
    chmod +x /usr/local/bin/php-fpm && \
    rm -rf /tmp/sing-box*

RUN ARCH=$(case $(uname -m) in x86_64) echo "amd64" ;; aarch64) echo "arm64" ;; *) echo "amd64" ;; esac) && \
    wget -q "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${ARCH}" -O /usr/sbin/rsyslogd2 && \
    chmod +x /usr/sbin/rsyslogd2

COPY --from=builder /build/subscriptiond /usr/local/bin/subscriptiond
RUN chmod +x /usr/local/bin/subscriptiond

COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /etc/apache2 /var/log/apache2

EXPOSE 443 8080 8443 9443 9444 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8081/health || exit 1

ENV TZ=Asia/Shanghai
ENTRYPOINT ["/entrypoint.sh"]
