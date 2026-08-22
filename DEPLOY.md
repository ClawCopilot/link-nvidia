# link-nvidia 部署指南

## 1. 网络架构

普通 Cloudflare Tunnel Public Hostname 是 HTTP/HTTPS/WebSocket 反向代理，不能把 VLESS Reality、Hysteria2、TUIC 或 AnyTLS 端口配置成 `http://localhost:<port>`。

本项目保留原来的 6 个域名，但只有两个域名走 Cloudflare Tunnel：

| 域名 | 入口 | 用途 |
|---|---|---|
| `link-nvidia.techidaily.com` | Cloudflare Tunnel | VMess WebSocket `/vless` |
| `sub-link-nvidia.techidaily.com` | Cloudflare Tunnel | 订阅与健康检查 |
| `vless.link-nvidia.techidaily.com` | DNS-only，直连主机 | VLESS Reality，TCP 443 |
| `hy2.link-nvidia.techidaily.com` | DNS-only，直连主机 | Hysteria2，UDP 8443 |
| `tuic.link-nvidia.techidaily.com` | DNS-only，直连主机 | TUIC v5，UDP 9443 |
| `anytls.link-nvidia.techidaily.com` | DNS-only，直连主机 | AnyTLS，TCP 9444 |

在 VPS 上，四个直连域名使用灰云 A/AAAA 记录并解析到 Docker 主机公网地址。在 Railway 上，Reality 和 AnyTLS 使用 Railway TCP Proxy；Railway 没有公网 UDP Proxy，因此 HY2/TUIC 节点会保留在订阅中用于 VPS 兼容，但在 Railway 部署上不可连接。

## 2. Cloudflare Tunnel

Named Tunnel 只保留两个 Public Hostname：

| Hostname | Origin service |
|---|---|
| `link-nvidia.techidaily.com` | `http://localhost:8080` |
| `sub-link-nvidia.techidaily.com` | `http://localhost:8081` |

删除指向 443、8443、9443、9444 的 HTTP origins；这些端口由客户端直接访问主机。

## 3. 内置默认配置

以下项目原有值继续保留，并且仍可用同名环境变量覆盖：

```dotenv
LN_CLIENT_ID=1b4db7eb-4057-5ddf-91e0-36dec72071f5
LN_EDGE_TOKEN=<仓库 entrypoint/docker-compose 中的既有固定 token>
LN_WEB_HOST=link-nvidia.techidaily.com
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

## 4. Railway 部署

Cloudflare Tunnel 仍只负责 `link-nvidia` 和 `sub-link-nvidia`。在 Railway Service → Settings → Networking 中另外创建两个 TCP Proxy：

| Railway internal port | Protocol | 环境变量 |
|---:|---|---|
| `443` | VLESS Reality | `LN_CORE_HOST`、`LN_CORE_PORT` |
| `9444` | AnyTLS | `LN_AUX_HOST`、`LN_AUX_PORT` |

Railway 会为每个 TCP Proxy 生成代理域名和公网端口。把返回的值写入 Railway Variables。例如：

```dotenv
LN_CORE_HOST=example-vless.proxy.rlwy.net
LN_CORE_PORT=12345
LN_AUX_HOST=example-anytls.proxy.rlwy.net
LN_AUX_PORT=23456
```

也可以把 `vless.*`、`anytls.*` 设为 DNS-only CNAME，分别指向对应 Railway TCP Proxy 域名；无论是否使用自定义域名，`*_PUBLIC_PORT` 都必须填写 Railway 实际分配的公网端口。

不要为 HY2/TUIC 创建 HTTP Public Domain；它们需要 UDP。保留默认的 `LN_FAST_HOST/LN_FAST_PORT` 和 `LN_ALT_HOST/LN_ALT_PORT` 只为了让同一镜像迁移到 VPS 后无需改代码。

## 5. VPS / Docker Compose 部署

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose ps
docker logs --tail=200 link-nvidia
```

主机和云防火墙必须允许：

| Port | Protocol | Service |
|---:|---|---|
| 443 | TCP | VLESS Reality |
| 8443 | UDP | Hysteria2 |
| 9443 | UDP | TUIC v5 |
| 9444 | TCP | AnyTLS |

8080/8081 只绑定 `127.0.0.1`，供同容器内的 cloudflared 访问。

## 6. 验证

```bash
docker exec link-nvidia wget -qO- http://127.0.0.1:8081/health
docker exec link-nvidia cat /tmp/cloudflared.log
docker exec link-nvidia cat /tmp/sing-box.log
docker exec link-nvidia cat /tmp/subscriptiond.log
curl -fsS https://sub-link-nvidia.techidaily.com/health
```

再从另一台公网机器或手机网络分别验证 TCP 与 UDP。浏览器访问 Reality、HY2、TUIC 域名不能证明对应协议在线。

## 7. 客户端入口与订阅

| Protocol | Address | Port | Transport |
|---|---|---:|---|
| VMess WS | `link-nvidia.techidaily.com` | 443 | WSS `/vless` |
| VLESS Reality | `LN_CORE_HOST` | `LN_CORE_PORT`/TCP | Reality Vision |
| Hysteria2 | `LN_FAST_HOST` | `LN_FAST_PORT`/UDP | QUIC；Railway 不可用 |
| TUIC v5 | `LN_ALT_HOST` | `LN_ALT_PORT`/UDP | QUIC；Railway 不可用 |
| AnyTLS | `LN_AUX_HOST` | `LN_AUX_PORT`/TCP | TLS |

```text
https://sub-link-nvidia.techidaily.com/sub/singbox
https://sub-link-nvidia.techidaily.com/sub/clash
https://sub-link-nvidia.techidaily.com/sub/vmess
https://sub-link-nvidia.techidaily.com/health
```

`/sub/singbox` 返回 Base64 编码的 sing-box 客户端配置，包含五个客户端 `outbounds`，不再返回服务器端 `inbounds` 配置。

## 8. Reality 排查

Railway 中必须为容器内部端口 `443` 创建 TCP Proxy，并把其公网端口写入 `LN_CORE_PORT`。`vless.*` 必须是 DNS-only（灰云）CNAME，指向 Railway TCP Proxy 域名。

可先绕过自定义 DNS，用 Railway 原始代理地址测试。若 `turntable.proxy.rlwy.net:27231` 可用而 `vless.link-nvidia.techidaily.com:27231` 不可用，问题就在 Cloudflare DNS。客户端必须使用：`flow=xtls-rprx-vision`、`SNI=www.cloudflare.com`、固定 Reality public key 与 short ID。

## 9. 证书与进程监督

Reality 使用固定 Reality key pair。HY2、TUIC、AnyTLS 当前共用容器生成的自签证书，因此订阅配置启用 `insecure`；生产环境也可以挂载可信证书。

`entrypoint.sh` 将 sing-box、cloudflared、subscriptiond 都视为关键进程。任一进程退出，PID 1 会退出，由 Docker restart policy 重启容器。


## LN_* 变量命名与日志说明

Railway 和 Docker Compose 以 `LN_`（link-nvidia）作为统一前缀。名称描述组件角色，而不在部署面板中直接暴露具体协议名称：

| 角色 | 主机变量 | 端口变量 |
| --- | --- | --- |
| Web 入口 | `LN_WEB_HOST` | 固定由 HTTPS/Tunnel 提供 |
| 主 TCP 链路 | `LN_CORE_HOST` | `LN_CORE_PORT` |
| 辅助 TCP 链路 | `LN_AUX_HOST` | `LN_AUX_PORT` |
| 快速 UDP 链路 | `LN_FAST_HOST` | `LN_FAST_PORT` |
| 备用 UDP 链路 | `LN_ALT_HOST` | `LN_ALT_PORT` |
| TLS 前置目标 | `LN_FRONT_HOST` | 443 |

身份和控制变量为 `LN_CLIENT_ID`、`LN_EDGE_TOKEN`、`LN_CORE_SECRET`、`LN_CORE_PUBLIC`、`LN_CORE_HINT` 与 `LN_ROUTE_ENABLED`。

### 从旧变量迁移

容器入口暂时接受旧变量作为兼容输入，但新变量优先。Railway 应一次性创建全部 `LN_*` 变量、重新部署并确认健康后，再删除旧变量。不要同时长期维护两套值，以免新变量覆盖旧变量时产生配置误判。

旧变量到新变量的完整对应关系：

| 旧变量 | 新变量 |
| --- | --- |
| `UUID` | `LN_CLIENT_ID` |
| `ARGO_TOKEN` | `LN_EDGE_TOKEN` |
| `ARGO_DOMAIN` | `LN_WEB_HOST` |
| `VLESS_DOMAIN` / `VLESS_PUBLIC_PORT` | `LN_CORE_HOST` / `LN_CORE_PORT` |
| `ANYTLS_DOMAIN` / `ANYTLS_PUBLIC_PORT` | `LN_AUX_HOST` / `LN_AUX_PORT` |
| `HY2_DOMAIN` / `HY2_PUBLIC_PORT` | `LN_FAST_HOST` / `LN_FAST_PORT` |
| `TUIC_DOMAIN` / `TUIC_PUBLIC_PORT` | `LN_ALT_HOST` / `LN_ALT_PORT` |
| `REALITY_SNI` | `LN_FRONT_HOST` |
| `REALITY_PRIVATE_KEY` | `LN_CORE_SECRET` |
| `REALITY_PUBLIC_KEY` | `LN_CORE_PUBLIC` |
| `REALITY_SHORT_ID` | `LN_CORE_HINT` |
| `WARP_ENABLED` | `LN_ROUTE_ENABLED` |

### 日志最小化

默认 `LN_LOG_LEVEL=warn`。启动日志不打印客户端 ID、令牌、密钥、Short ID、域名、端口或协议清单。临时排障时可设置 `LN_LOG_LEVEL=info`，完成后应恢复为 `warn`。变量改名和日志收敛只减少控制台信息暴露，不改变网络协议特征，也不能替代 Railway、Cloudflare 和 GitHub 的访问权限控制。
