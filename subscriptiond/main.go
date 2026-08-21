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
	flag.StringVar(&uuid, "uuid", "", "UUID")
	flag.StringVar(&port, "port", "8081", "HTTP port")
	flag.StringVar(&realityPublicKey, "reality-public-key", "", "Reality Public Key")
	flag.StringVar(&realityShortId, "reality-short-id", "", "Reality Short ID")
	flag.StringVar(&argoDomain, "argo-domain", "", "Argo domain")
	flag.DurationVar(&keepaliveInterval, "keepalive-interval", 10*time.Minute, "Keepalive interval")
}

type VMessNode struct {
	V       string `json:"v"`
	PS      string `json:"ps"`
	Add     string `json:"add"`
	Port    string `json:"port"`
	ID      string `json:"id"`
	AID     string `json:"aid"`
	Net     string `json:"net"`
	Type    string `json:"type"`
	Host    string `json:"host"`
	Path    string `json:"path"`
	TLS     string `json:"tls"`
	ALPN    string `json:"alpn,omitempty"`
	SNI     string `json:"sni,omitempty"`
	Seed    string `json:"seed,omitempty"`
	Peer    string `json:"peer,omitempty"`
	Mux     int    `json:"mux"`
	Msg     string `json:"msg,omitempty"`
	Desc    string `json:"desc,omitempty"`
	UDP     bool   `json:"udp,omitempty"`
	XUDP    bool   `json:"xudp,omitempty"`
	XTLS    bool   `json:"xtls,omitempty"`
	PLAIN   string `json:"pl,omitempty"`
	ENCRYPT string `json:"scy,omitempty"`
}

func main() {
	flag.Parse()

	if uuid == "" {
		log.Fatal("UUID is required")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/alive", aliveHandler)
	mux.HandleFunc("/sub/singbox", singboxSubHandler)
	mux.HandleFunc("/sub/clash", clashSubHandler)
	mux.HandleFunc("/sub/vmess", vmessSubHandler)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("subscriptiond started on port %s", port)

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

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func aliveHandler(w http.ResponseWriter, r *http.Request) {
	if argoDomain == "" {
		http.Error(w, "Argo not configured", http.StatusBadRequest)
		return
	}

	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	resp, err := client.Get(fmt.Sprintf("https://%s", argoDomain))
	if err != nil {
		log.Printf("Keepalive failed: %v", err)
		http.Error(w, fmt.Sprintf("Keepalive failed: %v", err), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf("Keepalive OK (%d)", resp.StatusCode)))
}

func singboxSubHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile("/etc/apache2/config.json")
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read config: %v", err), http.StatusInternalServerError)
		return
	}

	encoded := base64.StdEncoding.EncodeToString(data)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(encoded))
}

func clashSubHandler(w http.ResponseWriter, r *http.Request) {
	yaml := generateClashConfig()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(yaml))
}

func vmessSubHandler(w http.ResponseWriter, r *http.Request) {
	nodes := generateVmessLinks()
	result := strings.Join(nodes, "\n")
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(result))
}

func keepaliveWorker() {
	ticker := time.NewTicker(keepaliveInterval)
	defer ticker.Stop()

	for range ticker.C {
		client := &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			},
		}

		resp, err := client.Get(fmt.Sprintf("https://%s", argoDomain))
		if err != nil {
			log.Printf("Keepalive request failed: %v", err)
			continue
		}
		resp.Body.Close()
		log.Printf("Keepalive OK: %s -> %d", argoDomain, resp.StatusCode)
	}
}

func generateClashConfig() string {
	serverAddr := argoDomain
	if serverAddr == "" {
		serverAddr = "localhost"
	}

	return fmt.Sprintf(`port: 7890
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

  - name: "link-nvidia-vmess"
    type: vmess
    server: %s
    port: 8080
    uuid: %s
    alterId: 0
    security: auto
    network: ws
    ws-opts:
      path: /vless
      headers:
        Host: %s

  - name: "link-nvidia-hy2"
    type: hysteria2
    server: %s
    port: 8443
    password: %s
    alpn:
      - h3
    sni: www.bing.com
    skip-cert-verify: true

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
		serverAddr, uuid, realityPublicKey, realityShortId,
		serverAddr, uuid, uuid, serverAddr,
		serverAddr, uuid,
		serverAddr, uuid, uuid)
}

func generateVmessLinks() []string {
	serverAddr := argoDomain
	if serverAddr == "" {
		serverAddr = "localhost"
	}

	nodes := []string{}

	vmessTLS := VMessNode{
		V:    "2",
		PS:   "link-nvidia-vmess-tls",
		Add:  serverAddr,
		Port: "443",
		ID:   uuid,
		AID:  "0",
		Net:  "ws",
		Type: "none",
		Host: serverAddr,
		Path: "/vless?ed=2048",
		TLS:  "tls",
		Mux:  0,
	}

	tlsData, _ := json.Marshal(vmessTLS)
	nodes = append(nodes, fmt.Sprintf("vmess://%s", base64.StdEncoding.EncodeToString(tlsData)))

	vmessNoTLS := VMessNode{
		V:    "2",
		PS:   "link-nvidia-vmess",
		Add:  serverAddr,
		Port: "8080",
		ID:   uuid,
		AID:  "0",
		Net:  "ws",
		Type: "none",
		Host: serverAddr,
		Path: "/vless",
		TLS:  "",
		Mux:  0,
	}

	noTLSData, _ := json.Marshal(vmessNoTLS)
	nodes = append(nodes, fmt.Sprintf("vmess://%s", base64.StdEncoding.EncodeToString(noTLSData)))

	return nodes
}
