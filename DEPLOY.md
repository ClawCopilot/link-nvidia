# link-nvidia 部署指南

## 1. 正确的网络架构

普通 Cloudflare Tunnel Public Hostname 是 HTTP/HTTPS/WebSocket 反向代理，不应把 VLESS Reality、Hysteria2、TUIC 或 AnyTLS 端口配置成 `http://localhost:<port>`。

本项目采用混合架构：

```text
VMess WS 客户端 ─ HTTPS/WSS ─> Cloudflare Edge ─ Tunnel ─> localhost:8080
订阅客户端     ─ HTTPS     ─> Cloudflare Edge ─ Tunnel ─> localhost:8081

VLESS Reality ─ TCP 443  ────────────────────────────────> Docker Host:443/tcp
Hysteria2     ─ UDP 8443 ────────────────────────────────> Docker Host:8443/udp
TUIC v5       ─ UDP 9443 ────────────────────────────────> Docker Host:9443/udp
AnyTLS        ─ TCP 9444 ────────────────────────────────> Docker Host:9444/tcp
```

如果必须让任意 TCP/UDP 协议也经过 Cloudflare，需要使用支持相应 L4 协议的 Cloudflare 产品，不能用普通 HTTP Tunnel Public Hostname 冒充 L4 代理。

## 2. DNS

使用三个入口：

- `link-nvidia.techidaily.com`：Cloudflare Tunnel hostname，仅用于 VMess WebSocket。
- `sub.link-nvidia.techidaily.com`：Cloudflare Tunnel hostname，仅用于订阅/健康检查。
- `direct.link-nvidia.techidaily.com`：DNS-only（灰云）A/AAAA 记录，直接解析到 Docker 主机公网地址，供 Reality/HY2/TUIC/AnyTLS 使用。

`direct.*` 不能开启普通 Cloudflare HTTP proxy（橙云），否则 UDP 8443/9443 和非 HTTP TCP 协议不会按本项目设计工作。

如果部署平台没有可直接到达的公网 TCP+UDP 端口（尤其是 UDP 8443/9443），HY2/TUIC 无法按此方案部署。

## 3. Cloudflare Tunnel

Named Tunnel 只配置两个 Public Hostname：

| Hostname | Origin service | 用途 |
|---|---|---|
| `link-nvidia.techidaily.com` | `http://localhost:8080` | VMess WebSocket `/vless` |
| `sub.link-nvidia.techidaily.com` | `http://localhost:8081` | 订阅和健康检查 |

删除以下错误的 HTTP origins：

```text
http://localhost:443
http://localhost:8443
http://localhost:9443
http://localhost:9444
```

## 4. 内置默认配置

本项目有意内置以下默认值，并允许通过环境变量覆盖；这是项目既定部署设计，不需要在部署前轮换：

```dotenv
UUID=1b4db7eb-4057-5ddf-91e0-36dec72071f5
ARGO_TOKEN=<仓库 entrypoint/docker-compose 中的既有固定 token>
ARGO_DOMAIN=link-nvidia.techidaily.com
DIRECT_DOMAIN=direct.link-nvidia.techidaily.com
REALITY_SNI=www.microsoft.com
REALITY_PRIVATE_KEY=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw
REALITY_PUBLIC_KEY=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w
REALITY_SHORT_ID=3ff4bf41
```

`docker-compose.yml` 和 `entrypoint.sh` 保留这些原始默认值。部署平台仍可通过同名环境变量覆盖它们。

## 5. Docker 部署

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose ps
docker logs --tail=200 link-nvidia
```

主机/云防火墙必须允许：

| Port | Protocol | Service |
|---:|---|---|
| 443 | TCP | VLESS Reality |
| 8443 | UDP | Hysteria2 |
| 9443 | UDP | TUIC v5 |
| 9444 | TCP | AnyTLS |

8080/8081 在 Compose 中只绑定 `127.0.0.1`，避免绕过 Tunnel 暴露 HTTP origin。

## 6. 验证顺序

先验证容器内部：

```bash
docker exec link-nvidia wget -qO- http://127.0.0.1:8081/health
docker exec link-nvidia cat /tmp/cloudflared.log
docker exec link-nvidia cat /tmp/sing-box.log
docker exec link-nvidia cat /tmp/subscriptiond.log
```

再验证 Tunnel：

```bash
curl -fsS https://sub.link-nvidia.techidaily.com/health
```

最后从另一台公网机器/手机网络验证直连端口。TCP 与 UDP 必须分开测；浏览器访问 HY2/TUIC/Reality 域名不是有效健康检查。

## 7. 客户端入口

| Protocol | Address | Port | Path/transport |
|---|---|---:|---|
| VMess WS | `link-nvidia.techidaily.com` | 443 | WSS `/vless` |
| VLESS Reality | `DIRECT_DOMAIN` | 443/TCP | Reality Vision |
| Hysteria2 | `DIRECT_DOMAIN` | 8443/UDP | QUIC |
| TUIC v5 | `DIRECT_DOMAIN` | 9443/UDP | QUIC |
| AnyTLS | `DIRECT_DOMAIN` | 9444/TCP | TLS |
| Subscription | `sub.link-nvidia.techidaily.com` | 443 | HTTPS |

订阅端点：

```text
https://sub.link-nvidia.techidaily.com/sub/clash
https://sub.link-nvidia.techidaily.com/sub/vmess
https://sub.link-nvidia.techidaily.com/health
```

## 8. 进程监督

`entrypoint.sh` 将 sing-box、cloudflared、subscriptiond 都视为关键进程。任一进程退出，PID 1 会退出并让 Docker 的 restart policy 重启容器，避免 cloudflared 已死但容器仍显示 Running/Healthy 的假在线状态。

## 9. 证书说明

Reality 使用固定 Reality key pair。HY2/TUIC/AnyTLS 当前使用容器生成的自签证书，因此客户端配置需要允许该证书；生产环境也可以挂载与 `DIRECT_DOMAIN` 匹配的可信证书。
