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
UUID=1b4db7eb-4057-5ddf-91e0-36dec72071f5
ARGO_TOKEN=<仓库 entrypoint/docker-compose 中的既有固定 token>
ARGO_DOMAIN=link-nvidia.techidaily.com
VLESS_DOMAIN=vless.link-nvidia.techidaily.com
HY2_DOMAIN=hy2.link-nvidia.techidaily.com
TUIC_DOMAIN=tuic.link-nvidia.techidaily.com
ANYTLS_DOMAIN=anytls.link-nvidia.techidaily.com
VLESS_PUBLIC_PORT=443
HY2_PUBLIC_PORT=8443
TUIC_PUBLIC_PORT=9443
ANYTLS_PUBLIC_PORT=9444
REALITY_SNI=www.microsoft.com
REALITY_PRIVATE_KEY=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw
REALITY_PUBLIC_KEY=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w
REALITY_SHORT_ID=3ff4bf41
```

## 4. Railway 部署

Cloudflare Tunnel 仍只负责 `link-nvidia` 和 `sub-link-nvidia`。在 Railway Service → Settings → Networking 中另外创建两个 TCP Proxy：

| Railway internal port | Protocol | 环境变量 |
|---:|---|---|
| `443` | VLESS Reality | `VLESS_DOMAIN`、`VLESS_PUBLIC_PORT` |
| `9444` | AnyTLS | `ANYTLS_DOMAIN`、`ANYTLS_PUBLIC_PORT` |

Railway 会为每个 TCP Proxy 生成代理域名和公网端口。把返回的值写入 Railway Variables。例如：

```dotenv
VLESS_DOMAIN=example-vless.proxy.rlwy.net
VLESS_PUBLIC_PORT=12345
ANYTLS_DOMAIN=example-anytls.proxy.rlwy.net
ANYTLS_PUBLIC_PORT=23456
```

也可以把 `vless.*`、`anytls.*` 设为 DNS-only CNAME，分别指向对应 Railway TCP Proxy 域名；无论是否使用自定义域名，`*_PUBLIC_PORT` 都必须填写 Railway 实际分配的公网端口。

不要为 HY2/TUIC 创建 HTTP Public Domain；它们需要 UDP。保留默认的 `HY2_DOMAIN/HY2_PUBLIC_PORT` 和 `TUIC_DOMAIN/TUIC_PUBLIC_PORT` 只为了让同一镜像迁移到 VPS 后无需改代码。

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
| VLESS Reality | `VLESS_DOMAIN` | `VLESS_PUBLIC_PORT`/TCP | Reality Vision |
| Hysteria2 | `HY2_DOMAIN` | `HY2_PUBLIC_PORT`/UDP | QUIC；Railway 不可用 |
| TUIC v5 | `TUIC_DOMAIN` | `TUIC_PUBLIC_PORT`/UDP | QUIC；Railway 不可用 |
| AnyTLS | `ANYTLS_DOMAIN` | `ANYTLS_PUBLIC_PORT`/TCP | TLS |

```text
https://sub-link-nvidia.techidaily.com/sub/singbox
https://sub-link-nvidia.techidaily.com/sub/clash
https://sub-link-nvidia.techidaily.com/sub/vmess
https://sub-link-nvidia.techidaily.com/health
```

`/sub/singbox` 返回 Base64 编码的 sing-box 客户端配置，包含五个客户端 `outbounds`，不再返回服务器端 `inbounds` 配置。

## 8. Reality 排查

Railway 中必须为容器内部端口 `443` 创建 TCP Proxy，并把其公网端口写入 `VLESS_PUBLIC_PORT`。`vless.*` 必须是 DNS-only（灰云）CNAME，指向 Railway TCP Proxy 域名。

可先绕过自定义 DNS，用 Railway 原始代理地址测试。若 `turntable.proxy.rlwy.net:27231` 可用而 `vless.link-nvidia.techidaily.com:27231` 不可用，问题就在 Cloudflare DNS。客户端必须使用：`flow=xtls-rprx-vision`、`SNI=www.microsoft.com`、固定 Reality public key 与 short ID。

## 9. 证书与进程监督

Reality 使用固定 Reality key pair。HY2、TUIC、AnyTLS 当前共用容器生成的自签证书，因此订阅配置启用 `insecure`；生产环境也可以挂载可信证书。

`entrypoint.sh` 将 sing-box、cloudflared、subscriptiond 都视为关键进程。任一进程退出，PID 1 会退出，由 Docker restart policy 重启容器。
