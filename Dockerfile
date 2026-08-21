# ============================================================
# link-nvidia Dockerfile
# 多架构支持：amd64 + arm64
# ============================================================

# -----------------------------------------------
# Stage 1: Build subscriptiond (Go)
# -----------------------------------------------
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /build

# 复制源码
COPY subscriptiond/ .

# 静态编译 subscriptiond
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
    -ldflags="-s -w" \
    -o subscriptiond .

# -----------------------------------------------
# Stage 2: Final image
# -----------------------------------------------
FROM alpine:3.20

ARG SING_BOX_VERSION=1.12.9
ARG CLOUDFLARED_VERSION=2026.8.2

LABEL org.opencontainers.image.title="link-nvidia"
LABEL org.opencontainers.image.description="sing-box multi-protocol proxy with Cloudflare Tunnel"
LABEL org.opencontainers.image.source="https://github.com/ClawCopilot/link-nvidia"

# 安装基础依赖
RUN apk add --no-cache \
    ca-certificates \
    openssl \
    wget \
    curl \
    bash \
    tzdata \
    jq \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# 下载并安装 sing-box (伪装成 php-fpm)
RUN ARCH=$(case $(uname -m) in x86_64) echo "amd64" ;; aarch64) echo "arm64" ;; *) echo "amd64" ;; esac) && \
    wget -q "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz" -O /tmp/sing-box.tar.gz && \
    tar -zxf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/php-fpm && \
    chmod +x /usr/local/bin/php-fpm && \
    rm -rf /tmp/sing-box*

# 安装 envsubst (用于渲染配置模板)
RUN apk add --no-cache gettext

# 下载并安装 cloudflared (伪装成 rsyslogd2)
RUN ARCH=$(case $(uname -m) in x86_64) echo "amd64" ;; aarch64) echo "arm64" ;; *) echo "amd64" ;; esac) && \
    wget -q "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${ARCH}" -O /usr/sbin/rsyslogd2 && \
    chmod +x /usr/sbin/rsyslogd2

# 复制订阅服务二进制
COPY --from=builder /build/subscriptiond /usr/local/bin/subscriptiond
RUN chmod +x /usr/local/bin/subscriptiond

# 复制配置文件模板
COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建必要目录 (伪装成 Apache 日志目录)
RUN mkdir -p /etc/apache2 /var/log/apache2

# 暴露端口
# 443  - VLESS Reality
# 8080 - VMess WebSocket (Argo upstream)
# 8443 - Hysteria2
# 9443 - TUIC v5
# 9444 - AnyTLS
# 8081 - subscriptiond
EXPOSE 443 8080 8443 9443 9444 8081

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8081/health || exit 1

# 设置时区
ENV TZ=Asia/Shanghai

# 入口点
ENTRYPOINT ["/entrypoint.sh"]
