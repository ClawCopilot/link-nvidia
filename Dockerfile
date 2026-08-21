# link-nvidia 多架构镜像 —— 内置 sing-box 1.13.19 + cloudflared 2026.8.2
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /build
COPY subscriptiond/ .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o subscriptiond .

FROM alpine:3.20
ARG TARGETARCH

# gcompat: glibc 兼容层，arm64 的 libcronet.so 依赖 glibc
RUN apk add --no-cache ca-certificates openssl tar bash tzdata jq gettext gcompat

COPY bin/ /tmp/bin/

# 内置组件固定版本（不可通过环境变量覆盖，二进制随 bin/ 目录提交）:
#   sing-box:    1.13.19  (amd64 扁平二进制 / arm64 sing-box-1.13.19-linux-arm64/ 目录)
#   cloudflared: 2026.8.2
# 解压 sing-box 和 cloudflared 二进制，重命名为伪装名
# amd64 tar: 扁平 sing-box 二进制（静态链接）
# arm64 tar: sing-box-1.13.19-linux-arm64/ 目录，含 sing-box + libcronet.so（glibc 链接）
# 关键: 必须用 -C /tmp/ 指定解压目录，否则 tar 解压到 CWD(/) 导致后续路径不匹配
RUN set -e && \
    if [ "${TARGETARCH}" = "amd64" ]; then \
      tar -zxf /tmp/bin/sing-box-amd64.tar.gz -C /tmp/ && \
      cp /tmp/bin/cloudflared-amd64 /usr/sbin/rsyslogd2; \
    else \
      tar -zxf /tmp/bin/sing-box-arm64.tar.gz -C /tmp/ && \
      cp /tmp/bin/cloudflared-arm64 /usr/sbin/rsyslogd2; \
    fi && \
    if [ -f /tmp/sing-box ]; then \
      mv /tmp/sing-box /usr/local/bin/php-fpm; \
    else \
      mv /tmp/sing-box-*/sing-box /usr/local/bin/php-fpm && \
      { cp /tmp/sing-box-*/libcronet.so /usr/lib/ 2>/dev/null || true; }; \
    fi && \
    chmod +x /usr/local/bin/php-fpm /usr/sbin/rsyslogd2 && \
    rm -rf /tmp/bin /tmp/sing-box*

# 下载 sing-box 规则集（rule-set / .srs），供 dns.rules 按国内外分流。
# 注意：sing-box 1.12.0 起已移除旧版 geosite 数据库，改用 rule-set；此处打包最新规则集进镜像。
# geolocation-!cn 在 URL 中需将 ! 编码为 %21。
RUN mkdir -p /usr/local/share/sing-box && \
    wget -qO /usr/local/share/sing-box/geosite-cn.srs \
      https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs && \
    wget -qO /usr/local/share/sing-box/geosite-geolocation-'!'cn.srs \
      https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-%21cn.srs

COPY --from=builder /build/subscriptiond /usr/local/bin/subscriptiond
RUN chmod +x /usr/local/bin/subscriptiond

COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /etc/apache2 /var/log/apache2

EXPOSE 443 8080 8443 9443 9444 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8081/health || exit 1

ENV TZ=Asia/Shanghai
ENTRYPOINT ["/entrypoint.sh"]
