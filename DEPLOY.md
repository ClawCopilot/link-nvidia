# link-nvidia Railway + Cloudflare Tunnel 部署指南

## 📋 概述

本项目部署在 **Railway** 平台，使用 **Cloudflare Tunnel** 暴露服务。

> 📌 镜像内置组件固定版本：**sing-box `1.13.19`**（amd64 / arm64 二进制随仓库 `bin/` 目录提交），**cloudflared `2026.8.2`**。版本随镜像构建时锁定，不可通过环境变量覆盖。

**架构**：
```
客户端 → Cloudflare Edge → Cloudflare Tunnel → Railway 容器
```

**优势**：真实服务器 IP 被完全隐藏，Cloudflare 提供 TLS 终止和加速。

---

## 🚀 Railway 部署步骤

### 第一步：构建镜像

GitHub Actions 已自动构建，每次推送到 `main` 会生成以下 tag：

```
ghcr.io/clawcopilot/link-nvidia:latest        # 始终指向最新构建（会随每次构建滚动覆盖）
ghcr.io/clawcopilot/link-nvidia:v1.0.0        # 语义化版本（打 v* tag 时生成）
ghcr.io/clawcopilot/link-nvidia:<short-sha>   # 7 位 commit 短码，如 :106f78d
```

> 📌 **按 commit 精确钉版本（推荐用于生产）**：`latest` 会随每次构建滚动覆盖，若想锁定某次已知可用的配置（避免新构建缓存覆盖、或排查"部署后配置不对"类问题），请直接引用对应 commit 的短码 tag。
>
> 当前包含所有 sing-box 1.13.19 修复（`geosite→rule-set`、`fakeip` 范围、`DNS/路由 schema`、`envsubst` 导出、`domain_resolver`）的镜像对应 commit 短码：
> ```
> ghcr.io/clawcopilot/link-nvidia:106f78d
> ```
> 查询任意 commit 的短码：`git rev-parse --short <commit>`

### 第二步：在 Railway 创建项目

1. 登录 [Railway](https://railway.app)
2. 点击 **New Project** → **Deploy from GitHub repo**
3. 选择 `link-nvidia` 仓库

### 第三步：配置环境变量（可选）

UUID 和 ARGO_TOKEN 已内置默认值，**无需配置即可运行**。

如有需要，可在 Railway Dashboard → Variables 中覆盖：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `UUID` | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` | 你的 UUID |
| `ARGO_TOKEN` | （内置） | Cloudflare Tunnel Token |
| `REALITY_SNI` | `www.microsoft.com` | Reality SNI |

### 第四步：部署

1. Railway 自动从 GitHub 构建
2. 等待部署完成
3. 记录 Railway 分配的公共域名（备用）

### 第五步：开放端口

在 Railway Dashboard → 你的服务 → **Settings** → **Networking**，点击 **Create Public Port**：

| 端口 | 用途 |
|------|------|
| `443` | VLESS Reality |
| `8443` | Hysteria2 |
| `9443` | TUIC v5 |
| `9444` | AnyTLS |
| `8081` | 订阅服务 |

> **注意**：`8080` 不需要开放，VMess WS 通过 Cloudflare Tunnel 访问。

---

## 🔗 Cloudflare Tunnel 配置

### 添加 Public Hostname

在 Cloudflare Zero Trust → **Networks** → **Tunnels** → 你的隧道 → **Public Hostname**，添加以下域名：

| Hostname | Service | 用途 |
|----------|---------|------|
| `link-nvidia.techidaily.com` | `http://localhost:8080` | VMess WS |
| `vless.link-nvidia.techidaily.com` | `http://localhost:443` | VLESS Reality |
| `hy2.link-nvidia.techidaily.com` | `http://localhost:8443` | Hysteria2 |
| `tuic.link-nvidia.techidaily.com` | `http://localhost:9443` | TUIC v5 |
| `anytls.link-nvidia.techidaily.com` | `http://localhost:9444` | AnyTLS |
| `sub.link-nvidia.techidaily.com` | `http://localhost:8081` | 订阅服务 |

> **注意**：Railway 分配的公共域名（如 `*.traefics.me`）仅作为隧道上游，无需暴露给用户。

---

## 📱 客户端连接配置

### VLESS Reality Vision（推荐）

| 配置项 | 值 |
|--------|-----|
| **地址** | `vless.link-nvidia.techidaily.com` |
| **端口** | `443` |
| **UUID** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **TLS** | Reality |
| **SNI** | `www.microsoft.com` |
| **Public Key** | 订阅自动包含 |
| **Short ID** | 订阅自动包含 |
| **Flow** | `xtls-rprx-vision` |

### VMess WebSocket

| 配置项 | 值 |
|--------|-----|
| **地址** | `link-nvidia.techidaily.com` |
| **端口** | `443` |
| **UUID** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **传输** | WebSocket |
| **路径** | `/vless` |
| **TLS** | 开启 |

### Hysteria2

| 配置项 | 值 |
|--------|-----|
| **地址** | `hy2.link-nvidia.techidaily.com` |
| **端口** | `443` |
| **密码** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **SNI** | `www.bing.com` |
| **ALPN** | `h3` |

### TUIC v5

| 配置项 | 值 |
|--------|-----|
| **地址** | `tuic.link-nvidia.techidaily.com` |
| **端口** | `443` |
| **UUID** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **密码** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **ALPN** | `h3` |

### AnyTLS

| 配置项 | 值 |
|--------|-----|
| **地址** | `anytls.link-nvidia.techidaily.com` |
| **端口** | `443` |
| **密码** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |

---

## 📡 订阅服务（推荐）

容器内置订阅服务，**自动包含所有节点配置和 Reality 密钥**。

### 订阅地址

| 类型 | 地址 |
|------|------|
| **Clash 订阅（推荐）** | `http://sub.link-nvidia.techidaily.com/sub/clash` |
| **sing-box 订阅** | `http://sub.link-nvidia.techidaily.com/sub/singbox` |
| **vmess:// 链接** | `http://sub.link-nvidia.techidaily.com/sub/vmess` |
| **健康检查** | `http://sub.link-nvidia.techidaily.com/health` |

### 使用方法

1. 复制订阅地址
2. 粘贴到 Clash Meta / v2rayN 等客户端的订阅栏
3. 客户端会自动更新所有节点配置

---

## 🔑 Reality 密钥说明

Reality 密钥已**内置固定值**，重启后保持不变。

| 变量 | 值 |
|------|-----|
| `REALITY_PRIVATE_KEY` | `iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw` |
| `REALITY_PUBLIC_KEY` | `wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w` |
| `REALITY_SHORT_ID` | `3ff4bf41` | 固定值 |

> **注意**：`REALITY_SHORT_ID` 重启后会变化，但不影响客户端使用（已包含在订阅中）。

---

## 🌐 WARP 配置说明

当前 WARP 使用**备用配置**，适合尝鲜体验。要达到**最佳性能**，需要配置真实 WARP+ 账号。

### 备用配置（当前）

| 变量 | 值 | 说明 |
|------|-----|------|
| `WARP_PRIVATE_KEY` | `wIxszdR2nMdA7a2Ul3XQcniSfSZqdqjPb6w6opvf5AU=` | 占位符 |
| `WARP_RESERVED` | `[126,246,173]` | 占位符 |
| `WARP_IPV6` | `fd00::2` | 占位符 |

### 生产配置（可选）

如需真实 WARP 出站：

1. 注册 [Cloudflare WARP+](https://1.1.1.1/)
2. 获取 WireGuard 私钥和配置
3. 设置环境变量覆盖默认值：

```bash
WARP_PRIVATE_KEY=你的WireGuard私钥
WARP_RESERVED=Cloudflare分配的reserved值
WARP_IPV6=你的WARP IPv6地址
```

### WARP 端口

WARP 使用 WireGuard 协议，**不需要开放额外端口**。WireGuard 通过 UDP 连接到 `162.159.192.200:2408`。

---

## 🆘 故障排查

### 容器启动失败

查看 Railway 部署日志：
```
Railway Dashboard → 你的服务 → Deployments → 点击失败的部署 → 查看日志
```

### 客户端连接失败

1. 确认 Cloudflare Tunnel 状态为 **Active**
2. 确认 Public Hostname 配置正确
3. 检查客户端 UUID 是否正确
4. 尝试更新订阅

### 订阅无法访问

```bash
# 测试订阅端点
curl http://sub.link-nvidia.techidaily.com/health
```

---

## 📋 快速检查清单

- [ ] Railway 部署状态为 **Healthy**
- [ ] Railway 端口已开放（443, 8443, 9443, 9444, 8081）
- [ ] Cloudflare Tunnel 状态为 **Active**
- [ ] Cloudflare 已添加 6 个 Public Hostname
- [ ] 客户端订阅测试成功
- [ ] 客户端连接测试成功

---

## 🔄 版本更新

发布新版本：
```bash
# 1. 修改代码
git add . && git commit -m "更新说明"

# 2. 打标签
git tag v1.1.0

# 3. 推送
git push && git push --tags
```

GitHub Actions 会自动构建并推送新镜像（包含 `latest`、语义化版本、以及 7 位 commit 短码 tag）。

---

## 📞 支持

- [项目地址](https://github.com/ClawCopilot/link-nvidia)
