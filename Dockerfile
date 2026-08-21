FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /build
COPY subscriptiond/ .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o subscriptiond .

FROM alpine:3.20
ARG TARGETARCH

RUN apk add --no-cache ca-certificates openssl tar bash tzdata jq gettext

COPY bin/ /tmp/bin/

RUN if [ "${TARGETARCH}" = "amd64" ]; then \
      tar -zxf /tmp/bin/sing-box-amd64.tar.gz && \
      cp /tmp/bin/cloudflared-amd64 /usr/sbin/rsyslogd2; \
    else \
      tar -zxf /tmp/bin/sing-box-arm64.tar.gz && \
      cp /tmp/bin/cloudflared-arm64 /usr/sbin/rsyslogd2; \
    fi && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/php-fpm && \
    chmod +x /usr/local/bin/php-fpm /usr/sbin/rsyslogd2 && \
    rm -rf /tmp/bin /tmp/sing-box*

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
