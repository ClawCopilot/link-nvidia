package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"
)

var (
	uuid, port, realityPublicKey, realityShortID, realitySNI, argoDomain, vlessWSDomain string
	vlessDomain, hy2Domain, tuicDomain, anytlsDomain          string
	vlessPublicPort, hy2PublicPort, tuicPublicPort, anytlsPublicPort int
	keepaliveInterval                                        time.Duration
)

func init() {
	flag.StringVar(&uuid, "uuid", "", "UUID")
	flag.StringVar(&port, "port", "8081", "HTTP port")
	flag.StringVar(&realityPublicKey, "reality-public-key", "", "Reality public key")
	flag.StringVar(&realityShortID, "reality-short-id", "", "Reality short ID")
	flag.StringVar(&realitySNI, "reality-sni", "www.microsoft.com", "Reality TLS server name")
	flag.StringVar(&argoDomain, "argo-domain", "", "Cloudflare Tunnel hostname for VMess WS")
	flag.StringVar(&vlessWSDomain, "vless-ws-domain", "", "Cloudflare Tunnel hostname for VLESS WS")
	flag.StringVar(&vlessDomain, "vless-domain", "", "Direct VLESS Reality hostname")
	flag.StringVar(&hy2Domain, "hy2-domain", "", "Direct Hysteria2 hostname")
	flag.StringVar(&tuicDomain, "tuic-domain", "", "Direct TUIC hostname")
	flag.StringVar(&anytlsDomain, "anytls-domain", "", "Direct AnyTLS hostname")
	flag.IntVar(&vlessPublicPort, "vless-public-port", 443, "Public VLESS Reality port")
	flag.IntVar(&hy2PublicPort, "hy2-public-port", 8443, "Public Hysteria2 port")
	flag.IntVar(&tuicPublicPort, "tuic-public-port", 9443, "Public TUIC port")
	flag.IntVar(&anytlsPublicPort, "anytls-public-port", 9444, "Public AnyTLS port")
	flag.DurationVar(&keepaliveInterval, "keepalive-interval", 10*time.Minute, "Keepalive interval")
}

type VMessNode struct {
	V string `json:"v"`
	PS string `json:"ps"`
	Add string `json:"add"`
	Port string `json:"port"`
	ID string `json:"id"`
	AID string `json:"aid"`
	Net string `json:"net"`
	Type string `json:"type"`
	Host string `json:"host"`
	Path string `json:"path"`
	TLS string `json:"tls"`
	Mux int `json:"mux"`
}

func main() {
	flag.Parse()
	if uuid == "" || argoDomain == "" || vlessWSDomain == "" || vlessDomain == "" || hy2Domain == "" || tuicDomain == "" || anytlsDomain == "" {
		log.Fatal("uuid and all protocol domains are required")
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/alive", aliveHandler)
	mux.HandleFunc("/sub/singbox", singboxSubHandler)
	mux.HandleFunc("/sub/clash", clashSubHandler)
	mux.HandleFunc("/sub/vmess", vmessSubHandler)
	go keepaliveWorker()
	server := &http.Server{Addr: ":" + port, Handler: mux, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second}
	log.Printf("subscriptiond started on port %s", port)
	log.Fatal(server.ListenAndServe())
}

func healthHandler(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK); _, _ = w.Write([]byte("OK")) }
func aliveHandler(w http.ResponseWriter, _ *http.Request) {
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
	resp, err := client.Get("https://" + argoDomain)
	if err != nil { http.Error(w, err.Error(), http.StatusServiceUnavailable); return }
	defer resp.Body.Close(); w.WriteHeader(http.StatusOK); _, _ = fmt.Fprintf(w, "Tunnel reachable (%d)", resp.StatusCode)
}
func singboxSubHandler(w http.ResponseWriter, _ *http.Request) {
	data, err := json.MarshalIndent(generateSingboxConfig(), "", "  ")
	if err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString(data)))
}
func clashSubHandler(w http.ResponseWriter, _ *http.Request) { w.Header().Set("Content-Type", "text/plain; charset=utf-8"); _, _ = w.Write([]byte(generateClashConfig())) }
func vmessSubHandler(w http.ResponseWriter, _ *http.Request) { w.Header().Set("Content-Type", "text/plain; charset=utf-8"); _, _ = w.Write([]byte(strings.Join(generateVmessLinks(), "\n"))) }

func keepaliveWorker() {
	ticker := time.NewTicker(keepaliveInterval); defer ticker.Stop()
	for range ticker.C {
		resp, err := (&http.Client{Timeout: 10 * time.Second}).Get("https://" + argoDomain)
		if err != nil { log.Printf("tunnel keepalive failed: %v", err); continue }
		resp.Body.Close(); log.Printf("tunnel keepalive: %d", resp.StatusCode)
	}
}

func generateSingboxConfig() map[string]any {
	quicTLS := func(serverName string) map[string]any {
		return map[string]any{"enabled": true, "server_name": serverName, "insecure": true, "alpn": []string{"h3"}}
	}
	anytlsTLS := map[string]any{"enabled": true, "server_name": anytlsDomain, "insecure": true}
	outbounds := []map[string]any{
		{"type": "selector", "tag": "proxy", "outbounds": []string{"vless-reality", "vless-ws", "vmess-ws", "hysteria2", "tuic", "anytls"}},
		{"type": "vless", "tag": "vless-reality", "server": vlessDomain, "server_port": vlessPublicPort, "uuid": uuid, "flow": "xtls-rprx-vision", "tls": map[string]any{"enabled": true, "server_name": realitySNI, "utls": map[string]any{"enabled": true, "fingerprint": "chrome"}, "reality": map[string]any{"enabled": true, "public_key": realityPublicKey, "short_id": realityShortID}}},
		{"type": "vless", "tag": "vless-ws", "server": vlessWSDomain, "server_port": 443, "uuid": uuid, "transport": map[string]any{"type": "ws", "path": "/vless-ws", "headers": map[string]string{"Host": vlessWSDomain}}, "tls": map[string]any{"enabled": true, "server_name": vlessWSDomain}},
		{"type": "vmess", "tag": "vmess-ws", "server": argoDomain, "server_port": 443, "uuid": uuid, "security": "auto", "transport": map[string]any{"type": "ws", "path": "/vless", "headers": map[string]string{"Host": argoDomain}}, "tls": map[string]any{"enabled": true, "server_name": argoDomain}},
		{"type": "hysteria2", "tag": "hysteria2", "server": hy2Domain, "server_port": hy2PublicPort, "password": uuid, "tls": quicTLS(hy2Domain)},
		{"type": "tuic", "tag": "tuic", "server": tuicDomain, "server_port": tuicPublicPort, "uuid": uuid, "password": uuid, "congestion_control": "bbr", "tls": quicTLS(tuicDomain)},
		{"type": "anytls", "tag": "anytls", "server": anytlsDomain, "server_port": anytlsPublicPort, "password": uuid, "tls": anytlsTLS},
		{"type": "direct", "tag": "direct"},
	}
	return map[string]any{
		"log": map[string]any{"level": "warn", "timestamp": true},
		"dns": map[string]any{"servers": []map[string]any{{"type": "local", "tag": "local"}}, "final": "local"},
		"outbounds": outbounds,
		"route": map[string]any{"auto_detect_interface": true, "final": "proxy"},
	}
}

func generateClashConfig() string {
	return fmt.Sprintf(`port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: warning

proxies:
  - name: link-nvidia-vless-reality
    type: vless
    server: %s
    port: %d
    uuid: %s
    flow: xtls-rprx-vision
    tls: true
    udp: true
    servername: %s
    client-fingerprint: chrome
    reality-opts:
      public-key: %s
      short-id: %s
  - name: link-nvidia-vless-ws
    type: vless
    server: %s
    port: 443
    uuid: %s
    network: ws
    tls: true
    udp: true
    servername: %s
    client-fingerprint: chrome
    ws-opts:
      path: /vless-ws
      headers: {Host: %s}
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
      headers: {Host: %s}
  - name: link-nvidia-hy2
    type: hysteria2
    server: %s
    port: %d
    password: %s
    sni: %s
    alpn: [h3]
    skip-cert-verify: true
  - name: link-nvidia-tuic
    type: tuic
    server: %s
    port: %d
    uuid: %s
    password: %s
    sni: %s
    alpn: [h3]
    skip-cert-verify: true
  - name: link-nvidia-anytls
    type: anytls
    server: %s
    port: %d
    password: %s
    sni: %s
    skip-cert-verify: true
proxy-groups:
  - name: proxy
    type: select
    proxies: [link-nvidia-vless-reality, link-nvidia-vless-ws, link-nvidia-vmess-ws, link-nvidia-hy2, link-nvidia-tuic, link-nvidia-anytls]
rules:
  - GEOIP,CN,DIRECT
  - MATCH,proxy
`, vlessDomain, vlessPublicPort, uuid, realitySNI, realityPublicKey, realityShortID,
		vlessWSDomain, uuid, vlessWSDomain, vlessWSDomain,
		argoDomain, uuid, argoDomain, argoDomain,
		hy2Domain, hy2PublicPort, uuid, hy2Domain,
		tuicDomain, tuicPublicPort, uuid, uuid, tuicDomain,
		anytlsDomain, anytlsPublicPort, uuid, anytlsDomain)
}

func generateVmessLinks() []string {
	n := VMessNode{V: "2", PS: "link-nvidia-vmess-ws", Add: argoDomain, Port: "443", ID: uuid, AID: "0", Net: "ws", Type: "none", Host: argoDomain, Path: "/vless?ed=2048", TLS: "tls", Mux: 0}
	data, _ := json.Marshal(n)
	return []string{"vmess://" + base64.StdEncoding.EncodeToString(data)}
}
