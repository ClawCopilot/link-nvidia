FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
ARG SING_BOX_VERSION=1.13.19

WORKDIR /build

COPY subscriptiond/ .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o subscriptiond .

RUN apk add --no-cache git && \
    git clone --depth 1 --branch v${SING_BOX_VERSION} https://github.com/SagerNet/sing-box /tmp/sing-box && \
    cd /tmp/sing-box && \
    CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o sing-box . && \
    mv sing-box /build/php-fpm && \
    rm -rf /tmp/sing-box

FROM alpine:3.20
ARG CLOUDFLARED_VERSION=2026.8.2

RUN apk add --no-cache ca-certificates openssl curl bash tzdata jq gettext

COPY --from=builder /build/subscriptiond /usr/local/bin/subscriptiond
COPY --from=builder /build/php-fpm /usr/local/bin/php-fpm
RUN chmod +x /usr/local/bin/subscriptiond /usr/local/bin/php-fpm

RUN ARCH=$(case $(uname -m) in x86_64) echo "amd64" ;; aarch64) echo "arm64" ;; *) echo "amd64" ;; esac) && \
    wget "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${ARCH}" -O /usr/sbin/rsyslogd2 && \
    chmod +x /usr/sbin/rsyslogd2

COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /etc/apache2 /var/log/apache2

EXPOSE 443 8080 8443 9443 9444 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8081/health || exit 1

ENV TZ=Asia/Shanghai
ENTRYPOINT ["/entrypoint.sh"]
