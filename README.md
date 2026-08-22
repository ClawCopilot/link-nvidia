⚠️ 严正声明 (License & Copyright)
本项目采用 CC BY-NC 4.0 协议进行分发。
无论你是直接 Fork、修改源码还是重新分发，都必须保留原作者的署名，且严禁用于任何商业牟利行为。一经发现侵权，作者保留追究责任的权利。（支持YouTube等视频平台分享，但必须提供原项目地址）

# 🚀 link-nvidia — sing-box 多协议代理 Docker 镜像

[![Build & Push](https://github.com/ClawCopilot/link-nvidia/actions/workflows/main.yml/badge.svg)](https://github.com/ClawCopilot/link-nvidia/actions)
[![Docker Image](https://img.shields.io/docker/image-size/clawcopilot/link-nvidia/latest)](https://github.com/ClawCopilot/link-nvidia/pkgs/container/link-nvidia)
![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue)

本项目提供基于 **sing-box 1.13.19** + **Cloudflare Tunnel** 的多协议代理 Docker 镜像，支持 5 种主流代理协议，一条命令即可部署。

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| **5 种协议** | VLESS Reality Vision、VMess WebSocket、Hysteria2、TUIC v5、AnyTLS |
| **抗检测最强** | Reality (XTLS) + uTLS 指纹，伪装成 Chrome/Firefox 浏览器流量 |
| **WARP 出站** | 内置 WireGuard WARP，解锁 ChatGPT/Netflix/流媒体 |
| **Cloudflare Tunnel** | 仅承载 VMess WebSocket 与订阅服务；Reality/AnyTLS 使用直连 TCP |
| **订阅服务** | 内置 HTTP 服务，支持 sing-box JSON / Clash YAML / vmess:// |
| **进程管理** | PID 1 监督 sing-box、cloudflared、subscriptiond，异常时自动重启 |
| **多架构** | amd64 + arm64 原生支持 |
| **健康检查** | 内置 `/health` 端点，Docker HEALTHCHECK 就绪 |

## 📦 支持的协议

| 协议 | 端口 | 传输 | TLS | 适用场景 |
|------|------|------|-----|----------|
| **VLESS Reality Vision** | 443 | XTLS | Reality | 最强抗检测，推荐 |
| **VMess WebSocket** | 8080 | WebSocket | 可选 | 通用场景，兼容性好 |
| **Hysteria2** | 8443 | QUIC | h3 | 高带宽需求 |
| **TUIC v5** | 9443 | HTTP/3 | h3 | 低延迟场景 |
| **AnyTLS** | 9444 | TLS | 证书 | 深度伪装 |

## 🚀 快速开始

### VPS 最简部署

```bash
docker run -d \
  --name link-nvidia \
  -p 443:443 \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 9443:9443 \
  -p 8081:8081 \
  -e UUID=your-uuid-here \
  -e ARGO_TOKEN=your-argo-token-here \
  ghcr.io/clawcopilot/link-nvidia:latest
```

### docker-compose 部署

```yaml
services:
  link-nvidia:
    image: ghcr.io/clawcopilot/link-nvidia:latest
    container_name: link-nvidia
    restart: unless-stopped
    ports:
      - "443:443"     # VLESS Reality
      - "8080:8080"   # VMess WS
      - "8443:8443"   # Hysteria2
      - "9443:9443"   # TUIC v5
      - "9444:9444"   # AnyTLS
      - "8081:8081"   # 订阅服务
    environment:
      # 必填：你的 UUID
      UUID: your-uuid-here
      # Cloudflare Tunnel Token (可选，不填则用临时隧道)
      ARGO_TOKEN: your-argo-token-here
      # Reality SNI 目标
      LN_FRONT_HOST: www.cloudflare.com
      # 是否启用 WARP (默认 false)
      LN_ROUTE_ENABLED: "false"
    volumes:
      # 可选：持久化 Reality 密钥和 WARP 配置
      - ./data:/var/log/apache2
```

## 🔧 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `UUID` | ❌ | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` | 主 UUID，所有协议共用 |
| `ARGO_TOKEN` | ❌ | 使用内置token | Cloudflare Tunnel Token |
| `ARGO_DOMAIN` | ❌ | 自动获取 | 固定 Argo 域名 |
| `LN_FRONT_HOST` | ❌ | `www.cloudflare.com` | Reality 握手目标域名 |
| `LN_CORE_PUBLIC` | ❌ | 自动生成 | Reality 公钥 |
| `LN_CORE_SECRET` | ❌ | 自动生成 | Reality 私钥 |
| `LN_CORE_HINT` | ❌ | 随机 8 字符 | Reality 短 ID |
| `LN_ROUTE_ENABLED` | ❌ | `false` | 是否启用 WARP 出站 |
| `WARP_PRIVATE_KEY` | ❌ | 备用配置 | WARP 私钥 |
| `WARP_RESERVED` | ❌ | `[126,246,173]` | WARP reserved bytes |
| `KEEPALIVE_INTERVAL` | ❌ | `10m` | 保活间隔 |

> 📌 **内置组件版本（随镜像构建时固定，不可通过环境变量覆盖）**：
> - **sing-box**: `1.13.19`（amd64 / arm64 二进制已随仓库 `bin/` 目录提交）
> - **cloudflared**: `2026.8.2`
>
> ⚠️ **DNS 国内外分流说明**：sing-box 1.12.0 起已**移除**旧版 geosite/geoip 数据库机制，因此本镜像改用 **rule-set（`.srs` 规则集）** 实现分流——构建时从 SagerNet 仓库下载 `geosite-cn.srs` 与 `geosite-geolocation-!cn.srs` 打包进镜像，由 `dns.rules` 通过 `rule_set` 引用。配置模板中**不再出现** `geosite` 字段。

## 🚆 Railway 网络说明

Railway 上 VMess WS 与订阅通过 Cloudflare Tunnel；VLESS Reality 和 AnyTLS 通过 Railway TCP Proxy。HY2/TUIC 节点继续保留用于 VPS，但 Railway 没有公网 UDP 入站，不能在 Railway 上连接。Reality/AnyTLS 的公网端口必须分别通过 `LN_CORE_PORT`、`LN_AUX_PORT` 配置。

## 📡 订阅端点

容器内置订阅服务，自动包含所有协议配置和 Reality 密钥，**无需手动获取 Public Key**。

| 端点 | 说明 |
|------|------|
| `GET /sub/singbox` | sing-box JSON 配置 (base64 编码) |
| `GET /sub/clash` | Clash YAML 格式配置（推荐，自动包含 Reality 密钥） |
| `GET /sub/vmess` | vmess:// 分享链接 |
| `GET /health` | 健康检查 (返回 200 OK) |
| `GET /alive` | 触发 Argo 隧道保活 |

**订阅 URL 示例**：

```
# Clash Meta 客户端（推荐）
https://sub-link-nvidia.techidaily.com/sub/clash

# v2rayN / sing-box 客户端
https://sub-link-nvidia.techidaily.com/sub/singbox
```

## 🔐 客户端连接示例

> 💡 **推荐使用订阅方式**：直接导入 `https://sub-link-nvidia.techidaily.com/sub/clash`，自动包含所有配置和密钥。

### VLESS Reality Vision (推荐)

```
地址: your-domain.com
端口: 443
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
传输: (空)
安全: TLS
SNI: www.cloudflare.com
Reality: 启用
Public Key: (订阅自动包含)
Short ID: (订阅自动包含)
Flow: xtls-rprx-vision
```

### VMess WebSocket

```
地址: your-domain.com
端口: 8080
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
传输: WebSocket
路径: /vless
TLS: 关闭
```

### Hysteria2

```
地址: your-domain.com
端口: 8443
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
SNI: www.bing.com
ALPN: h3
```

### TUIC v5

```
地址: your-domain.com
端口: 9443
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
ALPN: h3
```

### AnyTLS

```
地址: your-domain.com
端口: 9444
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
```

## 🏗️ 项目结构

```
link-nvidia/
├── Dockerfile                          # 多架构 Docker 构建
├── entrypoint.sh                       # 容器启动脚本
├── templates/
│   └── config.yaml.template            # sing-box 配置模板
├── subscriptiond/
│   ├── main.go                         # Go 订阅服务
│   └── go.mod                          # Go 模块
├── docker-compose.yml                  # Docker Compose 部署配置
├── DEPLOY.md                           # Railway 部署指南
└── .github/workflows/
    └── main.yml                        # CI/CD 多架构构建
```

## 🐛 故障排查

### 容器启动失败

```bash
# 查看日志
docker logs link-nvidia

# 进入容器排查
docker exec -it link-nvidia sh
```

### Reality 密钥获取

```bash
# 查看公钥
cat /var/log/apache2/reality_public_key

# 查看私钥
cat /var/log/apache2/reality_private_key
```

### 订阅无法访问

```bash
# 检查 subscriptiond 是否运行
curl http://localhost:8081/health
```

## 📜 License

本项目采用 **CC BY-NC 4.0** 协议分发。

> ⚠️ 免责声明：本项目仅供学习和交流网络协议技术，请在遵守当地法律法规的前提下使用。

---

> **进阶玩法**：如果需要更高级的路由分流、流量统计、多用户管理等功能，可以基于本镜像进一步扩展。


## Configuration naming and logs

`UUID`, `ARGO_TOKEN`, and `ARGO_DOMAIN` retain their established names and embedded defaults. Endpoint variables use the `LN_*` prefix and role-based names such as `LN_CORE_HOST`, `LN_AUX_HOST`, `LN_FAST_HOST`, and `LN_ALT_HOST`. See [DEPLOY.md](DEPLOY.md#ln-变量命名与日志说明) for the migration table and Railway order of operations.

Runtime logging defaults to `LN_LOG_LEVEL=warn`. Startup output omits identifiers, keys, hostnames, ports, and protocol inventory. Use `info` only temporarily during troubleshooting. These controls reduce accidental log disclosure; they do not conceal network protocol characteristics or replace access control.
