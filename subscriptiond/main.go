// subscriptiond - link-nvidia 订阅 HTTP 服务
// 提供多格式订阅生成和保活机制
package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

var (
	uuid              string
	port              string
	realityPublicKey  string
	realityShortId    string
	argoDomain        string
	keepaliveInterval time.Duration
)

func init() {
	flag.StringVar(&uuid, "uuid", "", "主 UUID")
	flag.StringVar(&port, "port", "8081", "HTTP 服务端口")
	flag.StringVar(&realityPublicKey, "reality-public-key", "", "Reality Public Key")
	flag.StringVar(&realityShortId, "reality-short-id", "", "Reality Short ID")
	flag.StringVar(&argoDomain, "argo-domain", "", "Argo 固定域名")
	flag.DurationVar(&keepaliveInterval, "keepalive-interval", 10*time.Minute, "保活间隔")
}

type VMessNode struct {
	V      string `json:"v"`
	PS     string `json:"ps"`
	Add    string `json:"add"`
	Port   string `json:"port"`
	ID     string `json:"id"`
	AID    string `json:"aid"`
	Net    string `json:"net"`
	Type   string `json:"type"`
	Host   string `json:"host"`
	Path   string `json:"path"`
	TLS    string `json:"tls"`
	ALPN   string `json:"alpn,omitempty"`
	SNI    string `json:"sni,omitempty"`
	Seed   string `json:"seed,omitempty"`
	Peer   string `json:"peer,omitempty"`
	Mux    int    `json:"mux"`
	Msg    string `json:"msg,omitempty"`
	Desc   string `json:"desc,omitempty"`
	UDP    bool   `json:"udp,omitempty"`
	XUDP   bool   `json:"xudp,omitempty"`
	XTLS   bool   `json:"xtls,omitempty"`
	PLAIN  string `json:"pl,omitempty"`
	ENCRYPT string `json:"scy,omitempty"`
}

func main() {
	flag.Parse()

	if uuid == "" {
		log.Fatal("UUID is required")
	}

	// 启动 HTTP 服务
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/alive", aliveHandler)
	mux.HandleFunc("/sub/singbox", singboxSubHandler)
	mux.HandleFunc("/sub/clash", clashSubHandler)
	mux.HandleFunc("/sub/vmess", vmessSubHandler)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("subscriptiond 启动中，端口: %s", port)
	log.Printf("UUID: %s", uuid)
	log.Printf("Argo Domain: %s", argoDomain)
	log.Printf("保活间隔: %s", keepaliveInterval)

	// 启动保活协程
	if argoDomain != "" {
		go keepaliveWorker()
	}

	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	log.Fatal(server.ListenAndServe())
}

// healthHandler 健康检查
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

// aliveHandler 触发保活
func aliveHandler(w http.ResponseWriter, r *http.Request) {
	if argoDomain == "" {
		http.Error(w, "Argo not configured", http.StatusBadRequest)
		return
	}

	targetURL := fmt.Sprintf("https://%s", argoDomain)
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	resp, err := client.Get(targetURL)
	if err != nil {
		log.Printf("保活失败: %v", err)
		http.Error(w, fmt.Sprintf("Keepalive failed: %v", err), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf("Keepalive OK (%d)", resp.StatusCode)))
}

// singboxSubHandler 返回 sing-box JSON 配置 (base64)
func singboxSubHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile("/etc/apache2/config.json")
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read config: %v", err), http.StatusInternalServerError)
		return
	}

	// Base64 编码
	encoded := base64.StdEncoding.EncodeToString(data)

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(encoded))
}

// clashSubHandler 返回 Clash YAML 格式
func clashSubHandler(w http.ResponseWriter, r *http.Request) {
	yaml := generateClashConfig()

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(yaml))
}

// vmessSubHandler 返回 vmess:// 链接
func vmessSubHandler(w http.ResponseWriter, r *http.Request) {
	nodes := generateVmessLinks()
	result := strings.Join(nodes, "\n")

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(result))
}

// keepaliveWorker 定期保活协程
func keepaliveWorker() {
	ticker := time.NewTicker(keepaliveInterval)
	defer ticker.Stop()

	for range ticker.C {
		targetURL := fmt.Sprintf("https://%s", argoDomain)
		client := &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			},
		}

		resp, err := client.Get(targetURL)
		if err != nil {
			log.Printf("保活请求失败: %v", err)
			continue
		}
		resp.Body.Close()
		log.Printf("保活成功: %s -> %d", argoDomain, resp.StatusCode)
	}
}

// generateClashConfig 生成 Clash YAML 配置
func generateClashConfig() string {
	// 获取服务器地址
	serverAddr := argoDomain
	if serverAddr == "" {
		serverAddr = "localhost"
	}

	yaml := fmt.Sprintf(`# link-nvidia Clash 配置
# 生成时间: %s

port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fakeip
  fake-ip-range: 198.18.0.0/15
  nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies:
  # VLESS Reality Vision
  - name: "link-nvidia-vless"
    type: vless
    server: %s
    port: 443
    uuid: %s
    flow: xtls-rprx-vision
    tls: true
    udp: true
    sni: www.microsoft.com
    reality-opts:
      public-key: %s
      short-id: %s

  # VMess WebSocket
  - name: "link-nvidia-vmess"
    type: vmess
    server: %s
    port: 8080
    uuid: %s
    alterId: 0
    security: auto
    network: ws
    ws-opts:
      path: /%s-vm
      headers:
        Host: %s

  # Hysteria2
  - name: "link-nvidia-hy2"
    type: hysteria2
    server: %s
    port: 8443
    password: %s
    alpn:
      - h3
    sni: www.bing.com
    skip-cert-verify: true

  # TUIC v5
  - name: "link-nvidia-tuic"
    type: tuic
    server: %s
    port: 9443
    uuid: %s
    password: %s
    alpn:
      - h3
    sni: www.bing.com
    disable-sni: true
    udp-relay-mode: native

proxy-groups:
  - name: "auto"
    type: url-test
    proxies:
      - link-nvidia-vless
      - link-nvidia-vmess
      - link-nvidia-hy2
      - link-nvidia-tuic
    url: "http://www.gstatic.com/generate_204"
    interval: 300

  - name: "proxy"
    type: select
    proxies:
      - auto
      - link-nvidia-vless
      - link-nvidia-vmess
      - link-nvidia-hy2
      - link-nvidia-tuic

rules:
  - GEOIP,CN,DIRECT
  - MATCH,proxy
`,
		time.Now().Format("2006-01-02 15:04:05"),
		serverAddr, uuid, realityPublicKey, realityShortId,
		serverAddr, uuid, uuid, serverAddr,
		serverAddr, uuid,
		serverAddr, uuid, uuid)

	return yaml
}

// generateVmessLinks 生成 vmess:// 链接
func generateVmessLinks() []string {
	serverAddr := argoDomain
	if serverAddr == "" {
		serverAddr = "localhost"
	}

	nodes := []string{}

	// TLS 版本
	vmessTLS := VMessNode{
		V:     "2",
		PS:    "link-nvidia-vmess-tls",
		Add:   serverAddr,
		Port:  "443",
		ID:    uuid,
		AID:   "0",
		Net:   "ws",
		Type:  "none",
		Host:  serverAddr,
		Path:  "/vless?ed=2048",
		TLS:   "tls",
		Mux:   0,
	}

	tlsData, _ := json.Marshal(vmessTLS)
	nodes = append(nodes, fmt.Sprintf("vmess://%s", base64.StdEncoding.EncodeToString(tlsData)))

	// 非 TLS 版本
	vmessNoTLS := VMessNode{
		V:     "2",
		PS:    "link-nvidia-vmess",
		Add:   serverAddr,
		Port:  "8080",
		ID:    uuid,
		AID:   "0",
		Net:   "ws",
		Type:  "none",
		Host:  serverAddr,
		Path:  "/vless",
		TLS:   "",
		Mux:   0,
	}

	noTLSData, _ := json.Marshal(vmessNoTLS)
	nodes = append(nodes, fmt.Sprintf("vmess://%s", base64.StdEncoding.EncodeToString(noTLSData)))

	return nodes
}
