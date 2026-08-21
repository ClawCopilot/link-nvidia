# link-nvidia Railway 平台部署指南

## 📋 概述

Railway 是一个现代化的云平台，支持直接部署 Docker 镜像。本项目针对 Railway 进行了优化配置，开箱即用。

**重要**：Railway 会自动生成公共域名，无需额外配置 DNS。

---

## 🚀 Railway 部署步骤

### 第一步：构建并推送镜像到 GitHub Packages

```bash
# 1. 克隆/更新代码
cd link-nvidia

# 2. 本地构建 (可选，Railway 会自动从 GitHub 构建)
docker build -t ghcr.io/你的用户名/link-nvidia:latest .

# 3. 推送镜像
docker push ghcr.io/你的用户名/link-nvidia:latest
```

### 第二步：在 Railway 创建项目

1. 登录 [Railway](https://railway.app)
2. 点击 **New Project** → **Deploy from GitHub repo**
3. 选择 `link-nvidia` 仓库
4. 或点击 **New Project** → **Empty Project**，然后手动添加镜像

### 第三步：配置环境变量（可选）

ARGO_TOKEN 和 UUID 已内置默认值，无需配置。

如有需要，可在 Railway Dashboard → Variables 中覆盖：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `UUID` | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` | 你的 UUID |
| `ARGO_TOKEN` | （内置） | Cloudflare Tunnel Token（已内置，无需配置） |
| `REALITY_SNI` | `www.microsoft.com` | Reality SNI |

### 第四步：配置持久化存储

Railway 提供持久化磁盘（Volumes）：

1. 在 Railway Dashboard，进入 **Volumes**
2. 点击 **Create Volume**
3. 命名为 `sing-box-data`
4. 在服务设置中，挂载到 `/var/log/apache2`

或者直接添加环境变量指定挂载路径。

### 第五步：部署

1. Railway 会自动检测 Dockerfile 并构建
2. 等待构建完成（通常 2-5 分钟）
3. 部署完成后，Railway 会提供公共域名

---

## 🔗 Railway 公共域名

Railway 会为每个服务分配一个随机子域名，格式如：
```
xyz123abc-12345678901234-up-0-0-xxxxx-xxxxx-xxxxx.traefics.me
```

**在 Cloudflare Tunnel 中配置**：

1. 将 Argo Tunnel 的 **Public Hostname** 设置为你的自定义域名（如 `proxy.yourdomain.com`）
2. Service 指向 Railway 分配的公共域名 + 端口 `8080`

---

## 📱 Railway 上的客户端连接配置

### 获取 Railway 分配的域名

在 Railway Dashboard → 你的服务 → **Settings** → **Networking** → **Public Address**

### VLESS Reality Vision（推荐）

| 配置项 | Railway 值 |
|--------|-----------|
| **地址** | 你的自定义域名 或 Railway 公共域名 |
| **端口** | `443` |
| **UUID** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **TLS** | Reality |
| **SNI** | `www.microsoft.com` |
| **Public Key** | 见下方"获取 Reality 密钥" |
| **Short ID** | 见下方"获取 Reality 密钥" |
| **Flow** | `xtls-rprx-vision` |

### VMess WebSocket

| 配置项 | Railway 值 |
|--------|-----------|
| **地址** | Railway 公共域名 |
| **端口** | `443`（TLS）或 Railway 端口 |
| **UUID** | `1b4db7eb-4057-5ddf-91e0-36dec72071f5` |
| **传输** | WebSocket |
| **路径** | `/vless` |
| **TLS** | 开启 |

---

## 📡 订阅服务（推荐）

容器内置订阅服务，自动包含所有协议配置和 Reality 密钥，**无需手动获取 Public Key**。

### 订阅端点

| 端点 | 说明 |
|------|------|
| `GET /sub/clash` | Clash Meta 配置（推荐） |
| `GET /sub/singbox` | sing-box JSON 配置 |
| `GET /sub/vmess` | vmess:// 链接 |
| `GET /health` | 健康检查 |

### 使用方法

1. **Clash Meta 客户端**（推荐）：
   - 订阅地址：`http://服务器:8081/sub/clash`
   - 自动包含 Reality 密钥

2. **v2rayN / sing-box 客户端**：
   - 订阅地址：`http://服务器:8081/sub/singbox`

### Railway 订阅配置

Railway 部署后，确保端口已开放：

1. 进入 **Settings** → **Networking**
2. 点击 **Create Public Port**
3. 添加端口：`8081`
4. 订阅地址：`http://你的Railway域名:8081/sub/clash`

---

## 🔑 获取 Reality 密钥（如需手动配置）

如果客户端不支持订阅，或需要手动配置节点：

### Railway 终端

```bash
cat /var/log/apache2/reality_public_key
cat /var/log/apache2/reality_short_id
```

### 本地 Docker

```bash
docker exec link-nvidia cat /var/log/apache2/reality_public_key
docker exec link-nvidia cat /var/log/apache2/reality_short_id
```

---

## 📊 Railway 端口配置

Railway 的端口映射方式与 Docker 不同：

| 容器端口 | Railway 暴露 | 说明 |
|---------|--------------|------|
| `443` | Railway 自动分配 | VLESS Reality |
| `8080` | Railway 自动分配 | VMess WS + Argo 上游 |
| `8443` | Railway 自动分配 | Hysteria2 |
| `9443` | Railway 自动分配 | TUIC v5 |
| `9444` | Railway 自动分配 | AnyTLS |
| `8081` | Railway 自动分配 | 订阅服务 |

Railway 会自动将容器端口映射到公共端口，**无需手动映射**。

---

## 🔧 Railway 特定配置

### 使用 Railway 公共域名连接 Argo

Railway 的公共域名本身就可以用于 Argo 隧道：

```
# 你的 Railway 公共域名作为 Argo 上游
cloudflared tunnel --url http://localhost:8080
```

### 固定域名配置

如果你有自定义域名：

1. **Cloudflare 设置**：
   - CNAME 记录指向 Railway 公共域名
   - 或在 Argo Tunnel 中配置自定义域名

2. **Railway 设置**：
   - 在 **Networking** 中添加自定义域
   - Railway 会自动配置 SSL

---

## 🆘 Railway 故障排查

### 部署失败

```bash
# 查看构建日志
Railway Dashboard → 你的服务 → Deployments → 点击失败的部署 → 查看日志
```

### 服务无法启动

```bash
# Railway 终端调试
Railway Dashboard → 你的服务 → Terminal

# 手动启动测试
sh /entrypoint.sh
```

### 端口连接问题

Railway 默认不开放所有端口，需要在 **Networking** 中配置：

1. 进入服务 **Settings** → **Networking**
2. 点击 **Create Public Port**
3. 添加端口：`443`、`8080`、`8081`

### 持久化数据丢失

Railway 的 Volumes 需要显式配置：

1. 创建 Volume 并命名
2. 在服务中挂载：`/var/log/apache2` → 你的 Volume

---

## 🔒 Railway 安全建议

### 1. 环境变量保密

敏感信息（UUID、Argo Token）通过 Railway 环境变量设置，**不要**写在代码里。

### 2. 订阅服务访问控制

订阅端点 `/sub/*` 建议通过 Cloudflare Access 或 Railway 的自定义域名认证保护。

### 3. 防火墙

Railway 默认有基础防护，但建议：
- 只开放必要的端口
- 使用 Cloudflare Tunnel 隐藏真实 IP

---

## 📋 Railway 快速检查清单

- [ ] GitHub Packages 镜像已推送
- [ ] Railway 项目已创建
- [ ] 环境变量已配置（ARGO_TOKEN 必填）
- [ ] 持久化 Volume 已挂载
- [ ] 公共端口已开放（443, 8080, 8081）
- [ ] 部署状态为 **Healthy**
- [ ] Reality 密钥已获取
- [ ] 客户端测试连接成功

---

## 🔄 Railway 自动部署

Railway 支持 GitHub 集成，实现代码推送后自动部署：

1. 在 Railway 项目中连接 GitHub 仓库
2. 设置 **GitHub Connection**
3. 每次 `main` 分支推送后，Railway 会自动重新构建部署

---

## 📞 Railway 支持

- [Railway 文档](https://docs.railway.app)
- [Railway Discord](https://discord.gg/railway)

如遇问题，可先查看 Railway 官方文档或社区。
