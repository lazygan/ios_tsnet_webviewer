package tailbridge

import (
	"bytes"
	"net/netip"
	"strings"
	"testing"
)

func TestReadSocksConnectRequestIPv4(t *testing.T) {
	req := []byte{0x05, 0x01, 0x00, socksAtypIPv4, 100, 64, 0, 5, 0x1f, 0x90}
	host, port, err := readSocksConnectRequest(bytes.NewReader(req))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if host != "100.64.0.5" {
		t.Fatalf("host = %q, want 100.64.0.5", host)
	}
	if port != 8080 {
		t.Fatalf("port = %d, want 8080", port)
	}
}

func TestReadSocksConnectRequestDomain(t *testing.T) {
	domain := "nas.tailnet.ts.net"
	req := append([]byte{0x05, 0x01, 0x00, socksAtypDomain, byte(len(domain))}, []byte(domain)...)
	req = append(req, 0x00, 0x50)

	host, port, err := readSocksConnectRequest(bytes.NewReader(req))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if host != domain {
		t.Fatalf("host = %q, want %q", host, domain)
	}
	if port != 80 {
		t.Fatalf("port = %d, want 80", port)
	}
}

func TestReadSocksConnectRequestIPv6(t *testing.T) {
	addr := netip.MustParseAddr("fd7a:115c:a1e0::5")
	raw := addr.As16()
	req := append([]byte{0x05, 0x01, 0x00, socksAtypIPv6}, raw[:]...)
	req = append(req, 0x00, 0x50)

	host, port, err := readSocksConnectRequest(bytes.NewReader(req))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if host != addr.String() {
		t.Fatalf("host = %q, want %q", host, addr.String())
	}
	if port != 80 {
		t.Fatalf("port = %d, want 80", port)
	}
}

func TestReadSocksConnectRequestRejectsNonConnect(t *testing.T) {
	req := []byte{0x05, 0x02, 0x00, socksAtypIPv4, 100, 64, 0, 5, 0x1f, 0x90}
	if _, _, err := readSocksConnectRequest(bytes.NewReader(req)); err == nil {
		t.Fatal("expected error for non-CONNECT command")
	}
}

func TestReadSocksConnectRequestRejectsEmptyDomain(t *testing.T) {
	req := []byte{0x05, 0x01, 0x00, socksAtypDomain, 0x00, 0x00, 0x50}
	if _, _, err := readSocksConnectRequest(bytes.NewReader(req)); err == nil {
		t.Fatal("expected error for empty domain")
	}
}

func TestIsTailnetAddr(t *testing.T) {
	tests := []struct {
		addr string
		want bool
	}{
		{"100.64.0.1", true},
		{"100.127.255.254", true},
		{"100.63.255.255", false},
		{"100.128.0.1", false},
		{"8.8.8.8", false},
		{"fd7a:115c:a1e0::1", true},
		{"fd7a:115c:a1e1::1", false},
	}
	for _, tt := range tests {
		addr := netip.MustParseAddr(tt.addr)
		if got := isTailnetAddr(addr); got != tt.want {
			t.Errorf("isTailnetAddr(%s) = %v, want %v", tt.addr, got, tt.want)
		}
	}
}

func TestRedactSecrets(t *testing.T) {
	setLogSecret("tskey-secret-example-123")
	t.Cleanup(func() { setLogSecret("") })

	line := "auth tskey-secret-example-123 and tskey-another-456"
	got := redactSecrets(line)
	if strings.Contains(got, "secret-example") || strings.Contains(got, "another-456") {
		t.Fatalf("secret not redacted: %q", got)
	}
	if !strings.Contains(got, "tskey-REDACTED") {
		t.Fatalf("expected redaction marker, got %q", got)
	}
}

func TestRingLogKeepsBoundedLines(t *testing.T) {
	log := newRingLog(2)
	log.add("one")
	log.add("two")
	log.add("three")
	if got := log.String(); got != "two\nthree" {
		t.Fatalf("ring log = %q, want %q", got, "two\nthree")
	}
}
