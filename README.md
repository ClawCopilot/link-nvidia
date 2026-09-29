⚠️ 严正声明 (License & Copyright)
本项目采用 CC BY-NC 4.0 协议进行分发。
无论你是直接 Fork、修改源码还是重新分发，都必须保留原作者的署名，且严禁用于任何商业牟利行为。一经发现侵权，作者保留追究责任的权利。（支持YouTube等视频平台分享，但必须提供原项目地址）

# 🚀 link-nvidia — sing-box 多协议代理 Docker 镜像

[![Build & Push](https://github.com/ClawCopilot/link-nvidia/actions/workflows/main.yml/badge.svg)](https://github.com/ClawCopilot/link-nvidia/actions)
[![Docker Image](https://img.shields.io/docker/image-size/clawcopilot/link-nvidia/latest)](https://github.com/ClawCopilot/link-nvidia/pkgs/container/link-nvidia)
![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue)

本项目提供基于 **sing-box 1.13.21** + **Cloudflare Tunnel** 的多协议代理 Docker 镜像，支持 6 条代理通道，一条命令即可部署。

## 📑 目录

- [核心特性](#-核心特性)
- [支持的协议](#-支持的协议)
- [网络架构](#-网络架构)
- [快速开始（VPS）](#-快速开始vps)
- [Railway 部署（详细操作指南）](#-railway-部署详细操作指南)
- [环境变量](#-环境变量)
- [双 VLESS 通道](#-双-vless-通道)
- [订阅端点](#-订阅端点)
- [客户端连接示例](#-客户端连接示例)
- [验证与故障排查](#-验证与故障排查)
- [证书与进程监督](#-证书与进程监督)
- [项目结构](#-项目结构)
- [License](#-license)

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| **6 条通道** | VLESS Reality Vision、VLESS WebSocket、VMess WebSocket、Hysteria2、TUIC v5、AnyTLS |
| **抗检测最强** | Reality (XTLS) + uTLS 指纹，伪装成 Chrome/Firefox 浏览器流量 |
| **WARP 出站** | 内置 WireGuard WARP，解锁 ChatGPT/Netflix/流媒体 |
| **Cloudflare Tunnel** | 仅承载 VMess/VLESS WebSocket 与订阅服务；Reality/AnyTLS 使用直连 TCP |
| **订阅服务** | 内置 HTTP 服务，支持 v2rayN 分享链接 / sing-box JSON / Clash YAML / vmess:// |
| **进程管理** | PID 1 监督 sing-box、cloudflared、subscriptiond，异常时自动重启 |
| **多架构** | amd64 + arm64 原生支持 |
| **健康检查** | 内置 `/health` 端点，Docker HEALTHCHECK 就绪 |

## 📦 支持的协议

| 协议 | 容器内端口 | 传输 | TLS | 适用场景 |
|------|------|------|-----|----------|
| **VLESS Reality Vision** | 443 / TCP | XTLS | Reality | 最强抗检测，推荐 |
| **VLESS WebSocket** | 8082 / TCP | WebSocket | Cloudflare | CDN 中转，备用通道 |
| **VMess WebSocket** | 8080 / TCP | WebSocket | Cloudflare | 通用场景，兼容性好 |
| **Hysteria2** | 8443 / UDP | QUIC | 自签证书 | 高带宽需求 |
| **TUIC v5** | 9443 / UDP | HTTP/3 | 自签证书 | 低延迟场景 |
| **AnyTLS** | 9444 / TCP | TLS | 自签证书 | 深度伪装 |

> 平台可用性：VPS 上六条通道全部可用；Railway 上只有 **Reality / AnyTLS / VMess WS / VLESS WS** 可用（Railway 无公网 UDP 入站，HY2/TUIC 不可连接）。详见[网络架构](#-网络架构)与 [Railway 部署](#-railway-部署详细操作指南)。

## 🌐 网络架构

Cloudflare Tunnel 的 Public Hostname 是 HTTP/HTTPS/WebSocket 反向代理，**不能**把 VLESS Reality、Hysteria2、TUIC 或 AnyTLS 端口配置成 `http://localhost:<port>`。因此本项目保留 6 个域名，按通道类型分流：

| 域名 | 入口 | 用途 |
|---|---|---|
| `link-nvidia.techidaily.com` | Cloudflare Tunnel | VMess WebSocket `/vless`（容器 8080） |
| `sub-link-nvidia.techidaily.com` | Cloudflare Tunnel | 订阅与健康检查（容器 8081） |
| `ws-link-nvidia.techidaily.com` | Cloudflare Tunnel | VLESS WebSocket `/vless-ws`（容器 8082） |
| `vless.link-nvidia.techidaily.com` | DNS-only，直连主机 | VLESS Reality，TCP 443 |
| `hy2.link-nvidia.techidaily.com` | DNS-only，直连主机 | Hysteria2，UDP 8443 |
| `tuic.link-nvidia.techidaily.com` | DNS-only，直连主机 | TUIC v5，UDP 9443 |
| `anytls.link-nvidia.techidaily.com` | DNS-only，直连主机 | AnyTLS，TCP 9444 |

**Cloudflare Tunnel（Named Tunnel）只保留三条 Public Hostname：**

| Hostname | Path | Origin service |
|---|---|---|
| `link-nvidia.techidaily.com` | 留空 | `http://localhost:8080` |
| `sub-link-nvidia.techidaily.com` | 留空 | `http://localhost:8081` |
| `ws-link-nvidia.techidaily.com` | 留空 | `http://localhost:8082` |

保存 Published application 时 Cloudflare 会自动为同一 Tunnel 创建相应 DNS 记录，无需手工添加 CNAME。

**四个直连域名的接入方式因平台而异：**

- **VPS**：使用灰云（DNS-only）A/AAAA 记录解析到 Docker 主机公网地址，主机和云防火墙放行对应端口（见[快速开始](#-快速开始vps)）。
- **Railway**：Reality 和 AnyTLS 使用 **Railway TCP Proxy**（Railway 没有公网 UDP Proxy，HY2/TUIC 节点会保留在订阅中用于 VPS 兼容，但在 Railway 部署上不可连接）。

## 🚀 快速开始（VPS）

### docker run 最简部署

```bash
docker run -d \
  --name link-nvidia \
  --restart unless-stopped \
  -p 443:443/tcp \
  -p 8443:8443/udp \
  -p 9443:9443/udp \
  -p 9444:9444/tcp \
  -p 127.0.0.1:8080:8080/tcp \
  -p 127.0.0.1:8081:8081/tcp \
  -p 127.0.0.1:8082:8082/tcp \
  -e UUID=your-uuid-here \
  -e ARGO_TOKEN=your-argo-token-here \
  ghcr.io/clawcopilot/link-nvidia:latest
```

### docker-compose 部署

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose ps
docker logs --tail=200 link-nvidia
```

`docker-compose.yml` 关键内容（可直接复制）：

```yaml
services:
  link-nvidia:
    image: ghcr.io/clawcopilot/link-nvidia:latest
    container_name: link-nvidia
    restart: unless-stopped
    ports:
      - "443:443/tcp"     # VLESS Reality Vision
      - "8443:8443/udp"   # Hysteria2 / QUIC
      - "9443:9443/udp"   # TUIC v5 / QUIC
      - "9444:9444/tcp"   # AnyTLS
      - "127.0.0.1:8080:8080/tcp" # VMess WebSocket Tunnel origin
      - "127.0.0.1:8081:8081/tcp" # subscription/health Tunnel origin
      - "127.0.0.1:8082:8082/tcp" # VLESS WebSocket Tunnel origin
    environment:
      UUID: ${UUID:-1b4db7eb-4057-5ddf-91e0-36dec72071f5}
      ARGO_TOKEN: ${ARGO_TOKEN:-<内置 token>}
      ARGO_DOMAIN: ${ARGO_DOMAIN:-link-nvidia.techidaily.com}
      LN_ROUTE_ENABLED: ${LN_ROUTE_ENABLED:-false}
      LN_LOG_LEVEL: ${LN_LOG_LEVEL:-warn}
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
```

### 防火墙与端口要求

主机和云防火墙必须允许：

| Port | Protocol | Service |
|---:|---|---|
| 443 | TCP | VLESS Reality |
| 8443 | UDP | Hysteria2 |
| 9443 | UDP | TUIC v5 |
| 9444 | TCP | AnyTLS |

8080/8081/8082 只绑定 `127.0.0.1`，供同容器内的 cloudflared 访问，**不要**暴露到公网。

## 🚆 Railway 部署（详细操作指南）

Cloudflare Tunnel 只负责 `link-nvidia`（VMess WS）、`sub-link-nvidia`（订阅）和 `ws-link-nvidia`（VLESS WS）。VLESS Reality 和 AnyTLS 是非 HTTP 的原生 TCP 流量，必须走 **Railway TCP Proxy**；`LN_CORE_PORT` 和 `LN_AUX_PORT` 的值就来自 Railway 为 TCP Proxy 生成的公网端口。

> ⚠️ **前置认知**：容器内部监听端口固定为 `443`（Reality）和 `9444`（AnyTLS），不可通过环境变量修改；`LN_CORE_PORT` / `LN_AUX_PORT` 只决定**订阅中暴露给客户端的公网端口**。Railway 没有公网 UDP 入站，HY2/TUIC 在 Railway 上不可连接（相关默认值仅为迁移 VPS 保留）。

### 4.1 创建服务

1. 登录 [Railway](https://railway.app) → **New Project** → **Deploy from Docker Image**（或从 GitHub repo 部署）
2. 镜像填 `ghcr.io/clawcopilot/link-nvidia:latest`（生产建议钉 commit 短码 tag，如 `:33a2251`，用 `git rev-parse --short <commit>` 查询）
3. 等待首次部署完成；此时公网入口尚未创建，订阅中 Reality/AnyTLS 节点地址不可用，属预期

### 4.2 获得公网端口：创建 TCP Proxy

需要创建 **两个** TCP Proxy，分别对应容器内部端口 `443` 和 `9444`：

| Railway internal port | Protocol | 生成的值写入 |
|---:|---|---|
| `443` | VLESS Reality | `LN_CORE_HOST`、`LN_CORE_PORT` |
| `9444` | AnyTLS | `LN_AUX_HOST`、`LN_AUX_PORT` |

> ℹ️ Railway 官方已支持**每个服务多个 TCP Proxy**。旧版 CLI 文档中 "Only one TCP proxy is allowed per service instance" 是过时限制；若 CLI 操作时报此错误，先升级 Railway CLI 再重试。

> ℹ️ 代理域名与公网端口均由 **Railway 随机分配，不能自选**。公网端口不会是 443/9444，而是形如 `15140` 的随机高位端口——客户端连接时用的就是这个分配值，不是容器内端口。

#### 4.2.1 Dashboard 创建（对每个内部端口各做一次）

1. 打开 [Railway Dashboard](https://railway.app) → 在 Project 画布中点击你的 **Service** 卡片（不是 Project 总览页）
2. 在 Service 面板中点击 **Settings** 标签
3. 下拉找到 **Networking** 区域（部分界面版本为 **Public Networking** 小节）
4. 点击 **TCP Proxy**（部分界面版本显示为 Create Public Port / New Port，协议选择 **TCP**）
5. 在弹出的 **Application port**（内部端口）输入框填入 `443`，确认（按钮可能为 **Generate Domain**）
6. 重复第 4-5 步，内部端口填 `9444`

创建完成后，Networking 区域会列出两个 TCP Proxy 条目，格式形如：

```text
TCP · 443   →  shuttle.proxy.rlwy.net:15140
TCP · 9444  →  turntable.proxy.rlwy.net:27231
```

（域名和端口均为示例，以你面板实际显示为准。）每个条目提供复制按钮，可复制域名或完整 `域名:端口`。**域名部分**写入 `LN_*_HOST`，**端口部分**写入 `LN_*_PORT`。

#### 4.2.2 CLI 创建（等价方式）

已安装 Railway CLI 并 `railway link` 关联项目时：

```bash
railway tcp-proxy create --port 443    # 命令输出会直接打印生成的 domain:port
railway tcp-proxy create --port 9444
```

官方提示：若创建后代理未生效，重新部署服务并检查其状态。

#### 4.2.3 随时回查已分配的域名和端口

忘记端口时**无需删除重建**，三种方式任选：

```bash
# 方式一：Dashboard → Service → Settings → Networking，直接查看 TCP Proxy 条目

# 方式二：CLI 列出该服务全部代理（--json 便于脚本解析）
railway tcp-proxy list --service <服务名>
railway tcp-proxy list --service <服务名> --json

# 方式三：CLI 查询单个代理状态（参数可用 proxy ID、域名、端口号或应用端口）
railway tcp-proxy status shuttle.proxy.rlwy.net
```

#### 4.2.4 运行时自动注入的平台变量

Railway 会为配置了 TCP Proxy 的服务自动注入运行时变量：`RAILWAY_TCP_PROXY_DOMAIN`（代理域名）、`RAILWAY_TCP_PROXY_PORT`（公网端口）、`RAILWAY_TCP_APPLICATION_PORT`（内部端口）。可在容器内直接查看实际值：

```bash
railway ssh --service <服务名>
# 进入容器后执行：
env | grep RAILWAY_TCP
```

注意：官方文档仅明确**单个** TCP Proxy 时这些变量的含义；本项目有**两个** Proxy，变量与具体代理的对应关系没有文档保证。因此 `LN_*_HOST` / `LN_*_PORT` 应以 4.2.1 / 4.2.3 查到的实际值手动填写，不要直接引用平台变量。

### 4.3 配置变量：把获得的值写入 Railway Variables

**Dashboard 操作步骤**：

1. Service 页 → **Variables** 标签
2. 点击 **New Variable** 逐条添加（或用 Raw Editor 一次粘贴 dotenv 块）
3. 保存后，变量改动进入 **staged changes**——需点击 Variables 页出现的 **Deploy** 按钮（或 Deployments 页的 **Deploy latest**）应用变更并触发重新部署；旧版界面保存后即自动重新部署

以上一步生成的实际值为准，例如：

```dotenv
LN_CORE_HOST=shuttle.proxy.rlwy.net
LN_CORE_PORT=15140
LN_AUX_HOST=turntable.proxy.rlwy.net
LN_AUX_PORT=27231
```

**CLI 等价操作**：

```bash
railway variables --set "LN_CORE_HOST=shuttle.proxy.rlwy.net"
railway variables --set "LN_CORE_PORT=15140"
railway variables --set "LN_AUX_HOST=turntable.proxy.rlwy.net"
railway variables --set "LN_AUX_PORT=27231"
```

其余变量（`UUID`、`ARGO_TOKEN`、`ARGO_DOMAIN`、`LN_FAST_*`、`LN_ALT_*`、Reality 密钥等）均有内置默认值，无需设置。不要为 HY2/TUIC 创建 HTTP Public Domain；它们需要 UDP，Railway 不支持公网 UDP 入站，保留 `LN_FAST_HOST/LN_FAST_PORT` 和 `LN_ALT_HOST/LN_ALT_PORT` 默认值只是为了让同一镜像迁移到 VPS 后无需改代码。

### 4.4 可选：自定义域名（vless.* / anytls.*）

不配置自定义域名时，客户端直接使用 `xxx.proxy.rlwy.net:端口`。要使用自己的域名：

1. 在 Cloudflare DNS 中为 `vless.link-nvidia.techidaily.com` 添加 **CNAME** 记录：
   - **Name**：`vless`（按你的实际子域名）
   - **Target**：`shuttle.proxy.rlwy.net`（Railway 代理域名，**不带端口**）
   - **Proxy status**：**DNS only（灰云）** —— 必须关闭 Cloudflare 代理，橙云代理会破坏 Reality 握手和 AnyTLS 的 TLS 特征
2. `anytls.link-nvidia.techidaily.com` 同理，CNAME 指向 `turntable.proxy.rlwy.net`
3. 客户端连接时**仍使用 Railway 分配的端口**，自定义域名只替换主机名：

```dotenv
LN_CORE_HOST=vless.link-nvidia.techidaily.com
LN_CORE_PORT=15140
LN_AUX_HOST=anytls.link-nvidia.techidaily.com
LN_AUX_PORT=27231
```

### 4.5 部署并验证

保存变量后 Railway 自动重新部署。按顺序验证：

1. Service 部署状态为 **Healthy**（healthcheck 检测 `http://localhost:8081/health`）
2. 订阅服务健康：`curl -fsS https://sub-link-nvidia.techidaily.com/health`
3. TCP Proxy 直连测试（先绕过自定义 DNS，确认 Railway 侧正常）：

```bash
nc -zv shuttle.proxy.rlwy.net 15140
nc -zv turntable.proxy.rlwy.net 27231
```

4. 客户端重新导入订阅 `https://sub-link-nvidia.techidaily.com/sub/clash`，Reality/AnyTLS 节点的地址和端口应显示为 `LN_CORE_HOST:LN_CORE_PORT` / `LN_AUX_HOST:LN_AUX_PORT`

### 4.6 注意事项与常见坑

- **不要设置名为 `PORT` 的变量**：Railway 服务中若存在 `PORT` 变量，TCP Proxy 会忽略你在面板指定的内部端口，始终转发到 `PORT` 的值。本项目各端口变量均为专用名称（`SUBSCRIPTION_PORT` 等），不要额外新增 `PORT`。
- **删除并重建 TCP Proxy 会重新生成域名和端口**，必须同步更新 `LN_*_HOST` / `LN_*_PORT`。代理端点保存在服务配置中，正常重新部署不会重置；但社区存在重新部署后端口变化的个别案例，重新部署后建议核对 Networking 面板端口与 `LN_*_PORT` 是否一致。
- **客户端连不上时的第一检查项**：对比 TCP Proxy 面板上显示的端口与 Railway Variables 中 `LN_CORE_PORT` / `LN_AUX_PORT` 是否一致——两者不一致是最高频故障。
- **自定义域名排查**：若 `xxx.proxy.rlwy.net:端口` 可用而 `vless.link-nvidia.techidaily.com:端口` 不可用，问题在 Cloudflare DNS（大概率是橙云未关或 CNAME 目标填错）。

## 🔧 环境变量

### 基础变量表

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `UUID` | ❌ | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` | 主 UUID，所有协议共用 |
| `ARGO_TOKEN` | ❌ | 内置 token | Cloudflare Tunnel Token |
| `ARGO_DOMAIN` | ❌ | `link-nvidia.techidaily.com` | VMess WS 主机名（Tunnel） |
| `LN_WEB_ALT_HOST` | ❌ | `ws-link-nvidia.techidaily.com` | VLESS WS 主机名（Tunnel） |
| `LN_CORE_HOST` / `LN_CORE_PORT` | Railway ✅ | `vless.link-nvidia.techidaily.com` / `443` | Reality 节点地址与端口 |
| `LN_AUX_HOST` / `LN_AUX_PORT` | Railway ✅ | `anytls.link-nvidia.techidaily.com` / `9444` | AnyTLS 节点地址与端口 |
| `LN_FAST_HOST` / `LN_FAST_PORT` | ❌ | `hy2.link-nvidia.techidaily.com` / `8443` | Hysteria2 节点地址与端口 |
| `LN_ALT_HOST` / `LN_ALT_PORT` | ❌ | `tuic.link-nvidia.techidaily.com` / `9443` | TUIC v5 节点地址与端口 |
| `LN_FRONT_HOST` | ❌ | `www.cloudflare.com` | Reality 握手目标域名（SNI） |
| `LN_CORE_PUBLIC` | ❌ | 内置固定值 | Reality 公钥 |
| `LN_CORE_SECRET` | ❌ | 内置固定值 | Reality 私钥 |
| `LN_CORE_HINT` | ❌ | 内置固定值 | Reality Short ID |
| `LN_ROUTE_ENABLED` | ❌ | `false` | 是否启用 WARP 出站 |
| `WARP_PRIVATE_KEY` | ❌ | 备用配置 | WARP 私钥 |
| `WARP_RESERVED` | ❌ | `[126,246,173]` | WARP reserved bytes |
| `LN_LOG_LEVEL` | ❌ | `warn` | 日志级别（排障时临时用 `info`） |
| `KEEPALIVE_INTERVAL` | ❌ | `10m` | 保活间隔 |

> 📌 **内置组件版本（随镜像构建时固定，不可通过环境变量覆盖）**：
> - **sing-box**: `1.13.21`（amd64 / arm64 二进制已随仓库 `bin/` 目录提交）
> - **cloudflared**: `2026.9.1`
>
> ⚠️ **DNS 国内外分流说明**：sing-box 1.12.0 起已**移除**旧版 geosite/geoip 数据库机制，因此本镜像改用 **rule-set（`.srs` 规则集）** 实现分流——构建时从 SagerNet 仓库下载 `geosite-cn.srs` 与 `geosite-geolocation-!cn.srs` 打包进镜像，由 `dns.rules` 通过 `rule_set` 引用。配置模板中**不再出现** `geosite` 字段。

### 内置默认值

以下值已随镜像内置，仍可用同名环境变量覆盖：

```dotenv
UUID=1b4db7eb-4057-5ddf-91e0-36dec72071f5
ARGO_TOKEN=<仓库 entrypoint/docker-compose 中的既有固定 token>
ARGO_DOMAIN=link-nvidia.techidaily.com
LN_CORE_HOST=vless.link-nvidia.techidaily.com
LN_FAST_HOST=hy2.link-nvidia.techidaily.com
LN_ALT_HOST=tuic.link-nvidia.techidaily.com
LN_AUX_HOST=anytls.link-nvidia.techidaily.com
LN_CORE_PORT=443
LN_FAST_PORT=8443
LN_ALT_PORT=9443
LN_AUX_PORT=9444
LN_FRONT_HOST=www.cloudflare.com
LN_CORE_SECRET=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw
LN_CORE_PUBLIC=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w
LN_CORE_HINT=3ff4bf41
```

### LN_* 变量命名体系

`UUID`、`ARGO_TOKEN` 和 `ARGO_DOMAIN` 保持原名及原有默认值。其余端点变量以 `LN_`（link-nvidia）作为统一前缀，并用组件角色区分：

| 角色 | 主机变量 | 端口变量 |
| --- | --- | --- |
| Web 入口 | `ARGO_DOMAIN` | 固定由 HTTPS/Tunnel 提供 |
| 主 TCP 链路 | `LN_CORE_HOST` | `LN_CORE_PORT` |
| 辅助 TCP 链路 | `LN_AUX_HOST` | `LN_AUX_PORT` |
| 快速 UDP 链路 | `LN_FAST_HOST` | `LN_FAST_PORT` |
| 备用 UDP 链路 | `LN_ALT_HOST` | `LN_ALT_PORT` |
| TLS 前置目标 | `LN_FRONT_HOST` | 443 |

Reality 密钥及路由控制变量为 `LN_CORE_SECRET`、`LN_CORE_PUBLIC`、`LN_CORE_HINT` 与 `LN_ROUTE_ENABLED`。

### 从旧变量迁移

Railway 应保留 `UUID`、`ARGO_TOKEN` 和 `ARGO_DOMAIN`，只迁移端点、Reality 与路由相关变量。容器入口暂时接受这些待迁移项的旧名称，但 `LN_*` 新名称优先。创建新变量、重新部署并确认健康后，再删除对应旧变量。

| 旧变量 | 新变量 |
| --- | --- |
| `VLESS_DOMAIN` / `VLESS_PUBLIC_PORT` | `LN_CORE_HOST` / `LN_CORE_PORT` |
| `ANYTLS_DOMAIN` / `ANYTLS_PUBLIC_PORT` | `LN_AUX_HOST` / `LN_AUX_PORT` |
| `HY2_DOMAIN` / `HY2_PUBLIC_PORT` | `LN_FAST_HOST` / `LN_FAST_PORT` |
| `TUIC_DOMAIN` / `TUIC_PUBLIC_PORT` | `LN_ALT_HOST` / `LN_ALT_PORT` |
| `REALITY_SNI` | `LN_FRONT_HOST` |
| `REALITY_PRIVATE_KEY` | `LN_CORE_SECRET` |
| `REALITY_PUBLIC_KEY` | `LN_CORE_PUBLIC` |
| `REALITY_SHORT_ID` | `LN_CORE_HINT` |
| `WARP_ENABLED` | `LN_ROUTE_ENABLED` |

### Reality 密钥说明

`LN_CORE_SECRET`、`LN_CORE_PUBLIC` 和 `LN_CORE_HINT` 都是可选覆盖变量。镜像已经内置当前固定私钥、公钥和 Short ID；未设置这些变量时，会直接使用内置值，不会生成新值，也不会覆盖或改变现有密钥对。

因此常规部署**不需要**在 Railway 创建这三个变量。只有主动轮换 Reality 密钥时才应**同时设置**三个变量，并同步刷新客户端订阅。不要只覆盖公钥或私钥中的一项。

### 日志

默认 `LN_LOG_LEVEL=warn`。启动日志不打印客户端 ID、令牌、密钥、Short ID、域名、端口或协议清单。临时排障时可设置 `LN_LOG_LEVEL=info`，完成后应恢复为 `warn`。变量改名和日志收敛只减少控制台信息暴露，不改变网络协议特征，也不能替代 Railway、Cloudflare 和 GitHub 的访问权限控制。

运行日志使用 link-nvidia 角色命名：

| 路径 | 用途 |
| --- | --- |
| `/tmp/ln-core.log` | 核心网络服务日志 |
| `/tmp/ln-edge.log` | 边缘连接服务日志 |
| `/tmp/ln-web.log` | Web 与订阅服务日志 |

常用排障命令：`tail -f /tmp/ln-core.log`。文件名仅减少组件名称的直观暴露；日志内容仍由 `LN_LOG_LEVEL` 控制，文件本身没有加密。

## 🔀 双 VLESS 通道

镜像同时提供两条 VLESS 通道，与 VMess WS 并存：

- **VLESS Reality**：容器 TCP 443，VPS 直连公网端口，Railway 经 TCP Proxy 发布。抗检测首选。
- **VLESS WebSocket**：容器 TCP 8082，经 Cloudflare Tunnel 的独立主机名 `ws-link-nvidia.techidaily.com` 发布（默认值，由 `LN_WEB_ALT_HOST` 控制）。CDN 中转备用通道。
- **VMess WebSocket**：容器 TCP 8080，继续使用 `ARGO_DOMAIN`。

Cloudflare Tunnel 只需三条普通 Published application，不需要配置 Path 或规则顺序（见[网络架构](#-网络架构)中的 Tunnel 表）。

Railway **不需要**为 8082 创建 TCP Proxy，也不需要手工添加 DNS CNAME；Cloudflare 在保存 Published application 时会为同一 Tunnel 创建相应 DNS 记录。

VLESS WS 客户端连接参数：`ws-link-nvidia.techidaily.com:443`，路径 `/vless-ws`，TLS 由 Cloudflare 提供。

保存 Tunnel 配置后重新部署 Railway，并重新导入订阅。订阅中应同时出现 `link-nvidia-vless-reality` 和 `link-nvidia-vless-ws`。

## 📡 订阅端点

容器内置订阅服务，自动包含所有协议配置和 Reality 密钥，**无需手动获取 Public Key**。

| 端点 | 说明 |
|------|------|
| `GET /sub/v2ray` | v2rayN 订阅格式：6 条标准分享链接（vless / vmess / hysteria2 / tuic / anytls）整段 Base64 编码 |
| `GET /sub/singbox` | sing-box JSON 配置 (base64 编码) |
| `GET /sub/clash` | Clash YAML 格式配置（推荐，自动包含 Reality 密钥） |
| `GET /sub/vmess` | vmess:// 分享链接 |
| `GET /health` | 健康检查 (返回 200 OK) |
| `GET /alive` | 触发 Argo 隧道保活 |

**订阅 URL**：

```
https://sub-link-nvidia.techidaily.com/sub/clash      # Clash Meta 客户端（推荐）
https://sub-link-nvidia.techidaily.com/sub/v2ray      # v2rayN / v2rayNG 等分享链接订阅客户端
https://sub-link-nvidia.techidaily.com/sub/singbox    # sing-box 客户端
```

`/sub/v2ray` 返回 Base64 编码的标准分享链接列表（`vless://`、`vmess://`、`hysteria2://`、`tuic://`、`anytls://`，每行一条），这是 v2rayN 的原生订阅格式；`/sub/v2rayn` 是同一内容的别名。`/sub/singbox` 返回 Base64 编码的 sing-box 客户端配置，包含六个客户端 `outbounds`，不再返回服务器端 `inbounds` 配置——v2rayN 无法把该 JSON 解析为节点，v2rayN 用户请使用 `/sub/v2ray`。

## 🔐 客户端连接示例

> 💡 **推荐使用订阅方式**：Clash Meta 客户端导入 `https://sub-link-nvidia.techidaily.com/sub/clash`，v2rayN 导入 `https://sub-link-nvidia.techidaily.com/sub/v2ray`，自动包含所有配置和密钥。以下手动配置示例仅在无法使用订阅时参考。

### 节点总览

| Protocol | Address | Port | Transport |
|---|---|---:|---|
| VMess WS | `ARGO_DOMAIN` | 443 | WSS `/vless` |
| VLESS Reality | `LN_CORE_HOST` | `LN_CORE_PORT` / TCP | Reality Vision |
| VLESS WS | `LN_WEB_ALT_HOST` | 443 | WSS `/vless-ws` |
| Hysteria2 | `LN_FAST_HOST` | `LN_FAST_PORT` / UDP | QUIC；Railway 不可用 |
| TUIC v5 | `LN_ALT_HOST` | `LN_ALT_PORT` / UDP | QUIC；Railway 不可用 |
| AnyTLS | `LN_AUX_HOST` | `LN_AUX_PORT` / TCP | TLS |

### VLESS Reality Vision（推荐）

```
地址: LN_CORE_HOST 的值（VPS: vless.link-nvidia.techidaily.com / Railway: TCP Proxy 域名或自定义域名）
端口: LN_CORE_PORT 的值（VPS: 443 / Railway: Railway 分配的公网端口）
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
传输: (空)
安全: TLS
SNI: www.cloudflare.com
Reality: 启用
Public Key: (订阅自动包含)
Short ID: (订阅自动包含)
Flow: xtls-rprx-vision
```

### VLESS WebSocket

```
地址: ws-link-nvidia.techidaily.com
端口: 443
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
传输: WebSocket
路径: /vless-ws
TLS: 开启（由 Cloudflare 提供）
```

### VMess WebSocket

```
地址: link-nvidia.techidaily.com
端口: 443
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
传输: WebSocket
路径: /vless?ed=2048
Host: link-nvidia.techidaily.com
TLS: 开启（由 Cloudflare 提供）
```

### Hysteria2（仅 VPS）

```
地址: hy2.link-nvidia.techidaily.com
端口: 8443
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
SNI: hy2.link-nvidia.techidaily.com
ALPN: h3
跳过证书验证: 开启（自签证书）
```

### TUIC v5（仅 VPS）

```
地址: tuic.link-nvidia.techidaily.com
端口: 9443
UUID: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
SNI: tuic.link-nvidia.techidaily.com
ALPN: h3
跳过证书验证: 开启（自签证书）
```

### AnyTLS

```
地址: LN_AUX_HOST 的值（VPS: anytls.link-nvidia.techidaily.com / Railway: TCP Proxy 域名或自定义域名）
端口: LN_AUX_PORT 的值（VPS: 9444 / Railway: Railway 分配的公网端口）
密码: 1b4db7eb-4057-5ddf-91e0-36dec72071f5
SNI: 与地址相同
跳过证书验证: 开启（自签证书）
```

## ✅ 验证与故障排查

### 部署后验证

```bash
docker exec link-nvidia wget -qO- http://127.0.0.1:8081/health
docker exec link-nvidia cat /tmp/ln-edge.log
docker exec link-nvidia cat /tmp/ln-core.log
docker exec link-nvidia cat /tmp/ln-web.log
curl -fsS https://sub-link-nvidia.techidaily.com/health
```

再从另一台公网机器或手机网络分别验证 TCP 与 UDP。浏览器访问 Reality、HY2、TUIC 域名**不能**证明对应协议在线。

### 容器启动失败

```bash
docker logs link-nvidia          # 查看日志
docker exec -it link-nvidia sh   # 进入容器排查
```

### Reality 节点连不上

Railway 中必须为容器内部端口 `443` 创建 TCP Proxy，并把其公网端口写入 `LN_CORE_PORT`。`vless.*` 必须是 DNS-only（灰云）CNAME，指向 Railway TCP Proxy 域名。

可先绕过自定义 DNS，用 Railway 原始代理地址测试。若 `turntable.proxy.rlwy.net:27231` 可用而 `vless.link-nvidia.techidaily.com:27231` 不可用，问题就在 Cloudflare DNS。客户端必须使用：`flow=xtls-rprx-vision`、`SNI=www.cloudflare.com`、固定 Reality public key 与 short ID。

### Reality 密钥查看

```bash
cat /var/log/apache2/reality_public_key
cat /var/log/apache2/reality_private_key
```

### 订阅无法访问

```bash
curl http://localhost:8081/health   # 检查 subscriptiond 是否运行
```

## 🔐 证书与进程监督

Reality 使用固定 Reality key pair。HY2、TUIC、AnyTLS 当前共用容器生成的自签证书，因此订阅配置启用 `insecure`（跳过证书验证）；生产环境也可以挂载可信证书。

`entrypoint.sh` 将 sing-box、cloudflared、subscriptiond 都视为关键进程。任一进程退出，PID 1 会退出，由 Docker restart policy 重启容器。

## 📁 项目结构

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
└── .github/workflows/
    └── main.yml                        # CI/CD 多架构构建
```

## 📜 License

本项目采用 **CC BY-NC 4.0** 协议分发。

> ⚠️ 免责声明：本项目仅供学习和交流网络协议技术，请在遵守当地法律法规的前提下使用。

---

> **进阶玩法**：如果需要更高级的路由分流、流量统计、多用户管理等功能，可以基于本镜像进一步扩展。
