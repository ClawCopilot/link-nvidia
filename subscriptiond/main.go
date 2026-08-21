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
	uuid, port, realityPublicKey, realityShortID, argoDomain, directDomain string
	keepaliveInterval time.Duration
)

func init() {
	flag.StringVar(&uuid, "uuid", "", "UUID")
	flag.StringVar(&port, "port", "8081", "HTTP port")
	flag.StringVar(&realityPublicKey, "reality-public-key", "", "Reality public key")
	flag.StringVar(&realityShortID, "reality-short-id", "", "Reality short ID")
	flag.StringVar(&argoDomain, "argo-domain", "", "Cloudflare Tunnel hostname for VMess WS")
	flag.StringVar(&directDomain, "direct-domain", "", "Direct hostname/IP for Reality/HY2/TUIC/AnyTLS")
	flag.DurationVar(&keepaliveInterval, "keepalive-interval", 10*time.Minute, "Keepalive interval")
}

type VMessNode struct {
	V, PS, Add, Port, ID, AID, Net, Type, Host, Path, TLS string
	Mux int `json:"mux"`
}

func main() {
	flag.Parse()
	if uuid == "" || argoDomain == "" || directDomain == "" {
		log.Fatal("uuid, argo-domain and direct-domain are required")
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/alive", aliveHandler)
	mux.HandleFunc("/sub/singbox", singboxSubHandler)
	mux.HandleFunc("/sub/clash", clashSubHandler)
	mux.HandleFunc("/sub/vmess", vmessSubHandler)
	go keepaliveWorker()
	server := &http.Server{Addr: ":" + port, Handler: mux, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second}
	log.Printf("subscriptiond started on port %s (tunnel=%s direct=%s)", port, argoDomain, directDomain)
	log.Fatal(server.ListenAndServe())
}

func healthHandler(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK); _, _ = w.Write([]byte("OK")) }

func aliveHandler(w http.ResponseWriter, _ *http.Request) {
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
	resp, err := client.Get("https://" + argoDomain)
	if err != nil { http.Error(w, err.Error(), http.StatusServiceUnavailable); return }
	defer resp.Body.Close()
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprintf(w, "Tunnel reachable (%d)", resp.StatusCode)
}

func singboxSubHandler(w http.ResponseWriter, _ *http.Request) {
	data, err := os.ReadFile("/etc/apache2/config.json")
	if err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString(data)))
}

func clashSubHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(generateClashConfig()))
}

func vmessSubHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(strings.Join(generateVmessLinks(), "\n")))
}

func keepaliveWorker() {
	ticker := time.NewTicker(keepaliveInterval)
	defer ticker.Stop()
	for range ticker.C {
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Get("https://" + argoDomain)
		if err != nil { log.Printf("tunnel keepalive failed: %v", err); continue }
		resp.Body.Close()
		log.Printf("tunnel keepalive: %d", resp.StatusCode)
	}
}

func generateClashConfig() string {
	return fmt.Sprintf(`port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info

proxies:
  - name: link-nvidia-vless-reality
    type: vless
    server: %s
    port: 443
    uuid: %s
    flow: xtls-rprx-vision
    tls: true
    udp: true
    servername: www.microsoft.com
    reality-opts:
      public-key: %s
      short-id: %s

  - name: link-nvidia-vmess-ws
    type: vmess
    server: %s
    port: 443
    uuid: %s
    alterId: 0
    cipher: auto
    network: ws
    tls: true
    servername: %s
    ws-opts:
      path: /vless
      headers:
        Host: %s

  - name: link-nvidia-hy2
    type: hysteria2
    server: %s
    port: 8443
    password: %s
    sni: %s
    alpn: [h3]
    skip-cert-verify: true

  - name: link-nvidia-tuic
    type: tuic
    server: %s
    port: 9443
    uuid: %s
    password: %s
    sni: %s
    alpn: [h3]
    skip-cert-verify: true

  - name: link-nvidia-anytls
    type: anytls
    server: %s
    port: 9444
    password: %s
    sni: %s
    skip-cert-verify: true

proxy-groups:
  - name: proxy
    type: select
    proxies: [link-nvidia-vless-reality, link-nvidia-vmess-ws, link-nvidia-hy2, link-nvidia-tuic, link-nvidia-anytls]

rules:
  - GEOIP,CN,DIRECT
  - MATCH,proxy
`, directDomain, uuid, realityPublicKey, realityShortID,
		argoDomain, uuid, argoDomain, argoDomain,
		directDomain, uuid, directDomain,
		directDomain, uuid, uuid, directDomain,
		directDomain, uuid, directDomain)
}

func generateVmessLinks() []string {
	n := VMessNode{V: "2", PS: "link-nvidia-vmess-ws", Add: argoDomain, Port: "443", ID: uuid, AID: "0", Net: "ws", Type: "none", Host: argoDomain, Path: "/vless?ed=2048", TLS: "tls", Mux: 0}
	data, _ := json.Marshal(n)
	return []string{"vmess://" + base64.StdEncoding.EncodeToString(data)}
}
