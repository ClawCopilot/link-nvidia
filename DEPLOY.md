# link-nvidia 部署指南

## 1. 网络架构

普通 Cloudflare Tunnel Public Hostname 是 HTTP/HTTPS/WebSocket 反向代理，不能把 VLESS Reality、Hysteria2、TUIC 或 AnyTLS 端口配置成 `http://localhost:<port>`。

本项目保留原来的 6 个域名，但只有两个域名走 Cloudflare Tunnel：

| 域名 | 入口 | 用途 |
|---|---|---|
| `link-nvidia.techidaily.com` | Cloudflare Tunnel | VMess WebSocket `/vless` |
| `sub.link-nvidia.techidaily.com` | Cloudflare Tunnel | 订阅与健康检查 |
| `vless.link-nvidia.techidaily.com` | DNS-only，直连主机 | VLESS Reality，TCP 443 |
| `hy2.link-nvidia.techidaily.com` | DNS-only，直连主机 | Hysteria2，UDP 8443 |
| `tuic.link-nvidia.techidaily.com` | DNS-only，直连主机 | TUIC v5，UDP 9443 |
| `anytls.link-nvidia.techidaily.com` | DNS-only，直连主机 | AnyTLS，TCP 9444 |

四个直连域名必须是灰云 A/AAAA 记录，并解析到 Docker 主机公网地址。如果部署平台没有可直接到达的公网 TCP 和 UDP 端口，Reality、HY2、TUIC、AnyTLS 无法按此方案工作。

## 2. Cloudflare Tunnel

Named Tunnel 只保留两个 Public Hostname：

| Hostname | Origin service |
|---|---|
| `link-nvidia.techidaily.com` | `http://localhost:8080` |
| `sub.link-nvidia.techidaily.com` | `http://localhost:8081` |

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
REALITY_SNI=www.microsoft.com
REALITY_PRIVATE_KEY=iEN-abAE80W942AqjpS0k6a6UenauvBca45P1QTFLnw
REALITY_PUBLIC_KEY=wv6JL9uQquOEgd4Y5UOwYRspCsKkaxk3K8ePX1Xno2w
REALITY_SHORT_ID=3ff4bf41
```

## 4. Docker 部署

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

## 5. 验证

```bash
docker exec link-nvidia wget -qO- http://127.0.0.1:8081/health
docker exec link-nvidia cat /tmp/cloudflared.log
docker exec link-nvidia cat /tmp/sing-box.log
docker exec link-nvidia cat /tmp/subscriptiond.log
curl -fsS https://sub.link-nvidia.techidaily.com/health
```

再从另一台公网机器或手机网络分别验证 TCP 与 UDP。浏览器访问 Reality、HY2、TUIC 域名不能证明对应协议在线。

## 6. 客户端入口与订阅

| Protocol | Address | Port | Transport |
|---|---|---:|---|
| VMess WS | `link-nvidia.techidaily.com` | 443 | WSS `/vless` |
| VLESS Reality | `vless.link-nvidia.techidaily.com` | 443/TCP | Reality Vision |
| Hysteria2 | `hy2.link-nvidia.techidaily.com` | 8443/UDP | QUIC |
| TUIC v5 | `tuic.link-nvidia.techidaily.com` | 9443/UDP | QUIC |
| AnyTLS | `anytls.link-nvidia.techidaily.com` | 9444/TCP | TLS |

```text
https://sub.link-nvidia.techidaily.com/sub/singbox
https://sub.link-nvidia.techidaily.com/sub/clash
https://sub.link-nvidia.techidaily.com/sub/vmess
https://sub.link-nvidia.techidaily.com/health
```

`/sub/singbox` 返回 Base64 编码的 sing-box 客户端配置，包含五个客户端 `outbounds`，不再返回服务器端 `inbounds` 配置。

## 7. 证书与进程监督

Reality 使用固定 Reality key pair。HY2、TUIC、AnyTLS 当前共用容器生成的自签证书，因此订阅配置启用 `insecure`；生产环境也可以挂载可信证书。

`entrypoint.sh` 将 sing-box、cloudflared、subscriptiond 都视为关键进程。任一进程退出，PID 1 会退出，由 Docker restart policy 重启容器。
