package tailbridge

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

const (
	socksVersion5   = 0x05
	socksMethodNone = 0x00

	socksCmdConnect = 0x01

	socksAtypIPv4   = 0x01
	socksAtypDomain = 0x03
	socksAtypIPv6   = 0x04

	socksReplySuccess     = 0x00
	socksReplyFailure     = 0x01
	socksReplyNotAllowed  = 0x02
	socksReplyHostUnreach = 0x04
	socksReplyConnRefused = 0x05
)

var (
	tailnetV4 = netip.MustParsePrefix("100.64.0.0/10")
	tailnetV6 = netip.MustParsePrefix("fd7a:115c:a1e0::/48")

	errNotAllowed = errors.New("destination is not in the tailnet")

	connMu            sync.Mutex
	activeConnections = map[net.Conn]struct{}{}
)

func serveProxy(ctx context.Context, ln net.Listener, s *tsnet.Server) {
	logf("proxy: listening on %s", ln.Addr())
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			logf("proxy: accept failed: %v", err)
			return
		}
		go handleSocksConn(ctx, conn, s)
	}
}

func handleSocksConn(ctx context.Context, client net.Conn, s *tsnet.Server) {
	trackConnection(client)
	defer untrackConnection(client)

	_ = client.SetDeadline(time.Now().Add(20 * time.Second))

	if err := negotiateSocks(client); err != nil {
		logf("proxy: negotiation failed: %v", err)
		return
	}

	host, port, err := readSocksConnectRequest(client)
	if err != nil {
		logf("proxy: request failed: %v", err)
		_ = writeSocksReply(client, socksReplyFailure)
		return
	}

	target := net.JoinHostPort(host, strconv.Itoa(port))
	dialCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	upstream, err := dialTarget(dialCtx, s, host, port)
	if err != nil {
		switch {
		case errors.Is(err, errNotAllowed):
			logf("proxy: blocked %s (not in tailnet)", target)
			_ = writeSocksReply(client, socksReplyNotAllowed)
		case isDialRefused(err):
			logf("proxy: refused %s: %v", target, err)
			_ = writeSocksReply(client, socksReplyConnRefused)
		case isDialUnreachable(err):
			logf("proxy: unreachable %s: %v", target, err)
			_ = writeSocksReply(client, socksReplyHostUnreach)
		default:
			logf("proxy: dial %s failed: %v", target, err)
			_ = writeSocksReply(client, socksReplyFailure)
		}
		return
	}
	trackConnection(upstream)
	defer untrackConnection(upstream)

	if err := writeSocksReply(client, socksReplySuccess); err != nil {
		return
	}
	_ = client.SetDeadline(time.Time{})
	_ = upstream.SetDeadline(time.Time{})

	logf("proxy: connected %s", target)
	proxyCopy(client, upstream)
	logf("proxy: closed %s", target)
}

func negotiateSocks(c net.Conn) error {
	header := make([]byte, 2)
	if _, err := io.ReadFull(c, header); err != nil {
		return err
	}
	if header[0] != socksVersion5 {
		return fmt.Errorf("unsupported SOCKS version %d", header[0])
	}
	methodCount := int(header[1])
	if methodCount == 0 {
		return errors.New("no authentication methods offered")
	}
	methods := make([]byte, methodCount)
	if _, err := io.ReadFull(c, methods); err != nil {
		return err
	}
	_, err := c.Write([]byte{socksVersion5, socksMethodNone})
	return err
}

func readSocksConnectRequest(r io.Reader) (string, int, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(r, header); err != nil {
		return "", 0, err
	}
	if header[0] != socksVersion5 {
		return "", 0, fmt.Errorf("unsupported request version %d", header[0])
	}
	if header[1] != socksCmdConnect {
		return "", 0, fmt.Errorf("unsupported command %d", header[1])
	}

	var host string
	switch header[3] {
	case socksAtypIPv4:
		buf := make([]byte, net.IPv4len)
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", 0, err
		}
		host = net.IP(buf).String()
	case socksAtypIPv6:
		buf := make([]byte, net.IPv6len)
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", 0, err
		}
		host = net.IP(buf).String()
	case socksAtypDomain:
		lengthBuf := make([]byte, 1)
		if _, err := io.ReadFull(r, lengthBuf); err != nil {
			return "", 0, err
		}
		length := int(lengthBuf[0])
		if length == 0 {
			return "", 0, errors.New("empty domain name")
		}
		buf := make([]byte, length)
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", 0, err
		}
		host = string(buf)
	default:
		return "", 0, fmt.Errorf("unsupported address type %d", header[3])
	}

	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(r, portBuf); err != nil {
		return "", 0, err
	}
	port := int(portBuf[0])<<8 | int(portBuf[1])
	if port == 0 {
		return "", 0, errors.New("invalid port 0")
	}
	return host, port, nil
}

func writeSocksReply(c net.Conn, reply byte) error {
	_, err := c.Write([]byte{socksVersion5, reply, 0x00, socksAtypIPv4, 0, 0, 0, 0, 0, 0})
	return err
}

func dialTarget(ctx context.Context, s *tsnet.Server, host string, port int) (net.Conn, error) {
	if s == nil {
		return nil, errors.New("tailscale is not running")
	}
	portStr := strconv.Itoa(port)

	if addr, err := netip.ParseAddr(host); err == nil {
		if !isTailnetAddr(addr) {
			return nil, errNotAllowed
		}
		return s.Dial(ctx, "tcp", net.JoinHostPort(addr.String(), portStr))
	}

	key := strings.ToLower(strings.TrimSuffix(host, "."))
	stateMu.Lock()
	addrs := append([]netip.Addr(nil), peerHosts[key]...)
	stateMu.Unlock()
	if len(addrs) == 0 {
		return nil, errNotAllowed
	}

	var lastErr error
	for _, addr := range addrs {
		conn, err := s.Dial(ctx, "tcp", net.JoinHostPort(addr.String(), portStr))
		if err == nil {
			return conn, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = errNotAllowed
	}
	return nil, lastErr
}

func isTailnetAddr(addr netip.Addr) bool {
	addr = addr.Unmap()
	return tailnetV4.Contains(addr) || tailnetV6.Contains(addr)
}

func isDialRefused(err error) bool {
	var opErr *net.OpError
	if errors.As(err, &opErr) {
		return strings.Contains(strings.ToLower(opErr.Err.Error()), "refused")
	}
	return strings.Contains(strings.ToLower(err.Error()), "refused")
}

func isDialUnreachable(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unreachable") || strings.Contains(msg, "no route")
}

func proxyCopy(a, b net.Conn) {
	done := make(chan struct{}, 2)
	go func() {
		_, _ = io.Copy(a, b)
		if cw, ok := a.(interface{ CloseWrite() error }); ok {
			_ = cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		_, _ = io.Copy(b, a)
		if cw, ok := b.(interface{ CloseWrite() error }); ok {
			_ = cw.CloseWrite()
		}
		done <- struct{}{}
	}()

	<-done
	_ = a.SetDeadline(time.Now())
	_ = b.SetDeadline(time.Now())
	<-done
}

func trackConnection(c net.Conn) {
	connMu.Lock()
	activeConnections[c] = struct{}{}
	connMu.Unlock()
}

func untrackConnection(c net.Conn) {
	connMu.Lock()
	delete(activeConnections, c)
	connMu.Unlock()
	_ = c.Close()
}

func closeAllConnections() {
	connMu.Lock()
	conns := make([]net.Conn, 0, len(activeConnections))
	for c := range activeConnections {
		conns = append(conns, c)
	}
	activeConnections = map[net.Conn]struct{}{}
	connMu.Unlock()

	for _, c := range conns {
		_ = c.Close()
	}
}
