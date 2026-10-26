package tailbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tsnet"
)

const bridgeVersion = "0.1.0"

var (
	stateMu   sync.Mutex
	server    *tsnet.Server
	runCancel context.CancelFunc
	proxyLn   net.Listener
	proxyPort int
	lastError string
	peerHosts = map[string][]netip.Addr{}
)

type peerInfo struct {
	HostName     string   `json:"hostName"`
	DNSName      string   `json:"dnsName"`
	OS           string   `json:"os"`
	Online       bool     `json:"online"`
	TailscaleIPs []string `json:"tailscaleIPs"`
	ExitNode     bool     `json:"exitNode"`
}

type statusSnapshot struct {
	BackendState string     `json:"backendState"`
	AuthURL      string     `json:"authURL,omitempty"`
	Self         *peerInfo  `json:"self,omitempty"`
	Peers        []peerInfo `json:"peers"`
	ProxyPort    int        `json:"proxyPort"`
	ProxyRunning bool       `json:"proxyRunning"`
	LastError    string     `json:"lastError,omitempty"`
	Version      string     `json:"version"`
}

// Start creates the userspace Tailscale node and the loopback SOCKS5 proxy.
// It returns immediately; use StatusJSON to observe progress. Passing an empty
// hostname uses a default, and an empty controlURL uses the Tailscale cloud.
func Start(stateDir, hostname, authKey, controlURL string, requestedProxyPort int) error {
	Stop()

	if strings.TrimSpace(stateDir) == "" {
		return errors.New("state directory is required")
	}
	if requestedProxyPort < 0 || requestedProxyPort > 65535 {
		return fmt.Errorf("invalid proxy port %d", requestedProxyPort)
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return fmt.Errorf("create state directory: %w", err)
	}
	hostname = strings.TrimSpace(hostname)
	if hostname == "" {
		hostname = "tailweb-ios"
	}

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", requestedProxyPort))
	if err != nil && requestedProxyPort != 0 {
		logf("bridge: proxy port %d unavailable (%v); using an ephemeral port", requestedProxyPort, err)
		ln, err = net.Listen("tcp", "127.0.0.1:0")
	}
	if err != nil {
		return fmt.Errorf("start local proxy: %w", err)
	}
	port := 0
	if tcp, ok := ln.Addr().(*net.TCPAddr); ok {
		port = tcp.Port
	}

	ctx, cancel := context.WithCancel(context.Background())
	s := &tsnet.Server{
		Dir:        stateDir,
		Hostname:   hostname,
		AuthKey:    authKey,
		ControlURL: controlURL,
		Logf:       func(format string, args ...any) { logf("tsnet: "+format, args...) },
	}

	setLogSecret(authKey)

	stateMu.Lock()
	server = s
	runCancel = cancel
	proxyLn = ln
	proxyPort = port
	lastError = ""
	peerHosts = map[string][]netip.Addr{}
	stateMu.Unlock()

	logf("bridge: starting hostname=%s proxyPort=%d", hostname, port)

	go serveProxy(ctx, ln, s)
	go func() {
		st, err := s.Up(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			setLastError(fmt.Sprintf("tailscale up: %v", err))
			logf("bridge: tailscale up failed: %v", err)
			return
		}
		if st != nil {
			logf("bridge: tailscale state=%s", st.BackendState)
		}
	}()

	return nil
}

// Stop shuts down tsnet, closes the proxy and all active tunnels.
func Stop() {
	stateMu.Lock()
	cancel := runCancel
	s := server
	ln := proxyLn
	runCancel = nil
	server = nil
	proxyLn = nil
	proxyPort = 0
	peerHosts = map[string][]netip.Addr{}
	lastError = ""
	stateMu.Unlock()

	if cancel != nil {
		cancel()
	}
	if ln != nil {
		_ = ln.Close()
	}
	if s != nil {
		_ = s.Close()
	}
	closeAllConnections()
	logf("bridge: stopped")
}

// StatusJSON returns a snapshot for the Swift poller.
func StatusJSON() string {
	stateMu.Lock()
	s := server
	port := proxyPort
	errMsg := lastError
	stateMu.Unlock()

	snap := statusSnapshot{
		BackendState: "Stopped",
		ProxyPort:    port,
		ProxyRunning: port > 0,
		LastError:    errMsg,
		Version:      bridgeVersion,
		Peers:        []peerInfo{},
	}

	if s != nil {
		snap.BackendState = "Starting"
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		lc, err := s.LocalClient()
		if err != nil {
			snap.LastError = firstNonEmpty(errMsg, err.Error())
		} else if st, err := lc.Status(ctx); err != nil {
			snap.LastError = firstNonEmpty(errMsg, err.Error())
		} else {
			fillStatus(&snap, st)
			updatePeerHosts(st)
		}
	}

	b, err := json.Marshal(snap)
	if err != nil {
		return `{"backendState":"Error","peers":[],"proxyPort":0,"proxyRunning":false,"lastError":"status marshal failed"}`
	}
	return string(b)
}

func fillStatus(snap *statusSnapshot, st *ipnstate.Status) {
	snap.BackendState = string(st.BackendState)
	snap.AuthURL = st.AuthURL
	snap.Self = convertPeer(st.Self)
	for _, ps := range st.Peer {
		if p := convertPeer(ps); p != nil {
			snap.Peers = append(snap.Peers, *p)
		}
	}
	sort.Slice(snap.Peers, func(i, j int) bool {
		if snap.Peers[i].Online != snap.Peers[j].Online {
			return snap.Peers[i].Online
		}
		return strings.ToLower(snap.Peers[i].HostName) < strings.ToLower(snap.Peers[j].HostName)
	})
}

func convertPeer(ps *ipnstate.PeerStatus) *peerInfo {
	if ps == nil {
		return nil
	}
	ips := make([]string, 0, len(ps.TailscaleIPs))
	for _, ip := range ps.TailscaleIPs {
		ips = append(ips, ip.String())
	}
	dns := strings.TrimSuffix(ps.DNSName, ".")
	host := ps.HostName
	if host == "" {
		host = dns
	}
	return &peerInfo{
		HostName:     host,
		DNSName:      dns,
		OS:           ps.OS,
		Online:       ps.Online,
		TailscaleIPs: ips,
		ExitNode:     ps.ExitNode,
	}
}

func updatePeerHosts(st *ipnstate.Status) {
	hosts := map[string][]netip.Addr{}
	add := func(ps *ipnstate.PeerStatus) {
		if ps == nil {
			return
		}
		keys := make([]string, 0, 2)
		if ps.HostName != "" {
			keys = append(keys, ps.HostName)
		}
		if dns := strings.TrimSuffix(ps.DNSName, "."); dns != "" {
			keys = append(keys, dns)
		}
		for _, key := range keys {
			key = strings.ToLower(strings.TrimSuffix(key, "."))
			for _, ip := range ps.TailscaleIPs {
				hosts[key] = append(hosts[key], ip)
			}
		}
	}
	add(st.Self)
	for _, ps := range st.Peer {
		add(ps)
	}

	stateMu.Lock()
	peerHosts = hosts
	stateMu.Unlock()
}

func setLastError(msg string) {
	stateMu.Lock()
	lastError = msg
	stateMu.Unlock()
}

// Logs returns the in-memory log buffer with secrets redacted.
func Logs() string {
	return bridgeLog.String()
}

func ClearLogs() {
	bridgeLog.clear()
}

func Version() string {
	return bridgeVersion
}

// ResetIdentity stops the node and deletes its persisted state directory.
func ResetIdentity(stateDir string) error {
	Stop()
	if strings.TrimSpace(stateDir) == "" {
		return errors.New("state directory is required")
	}
	if err := os.RemoveAll(stateDir); err != nil {
		return fmt.Errorf("remove state directory: %w", err)
	}
	logf("bridge: identity reset")
	return nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
