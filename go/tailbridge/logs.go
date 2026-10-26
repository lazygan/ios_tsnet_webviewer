package tailbridge

import (
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"
)

const maxLogLines = 500

var tskeyPattern = regexp.MustCompile(`tskey-[A-Za-z0-9_-]+`)

type ringLog struct {
	mu    sync.Mutex
	lines []string
	max   int
}

func newRingLog(max int) *ringLog {
	if max <= 0 {
		max = maxLogLines
	}
	return &ringLog{max: max}
}

func (r *ringLog) add(line string) {
	line = redactSecrets(line)
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lines = append(r.lines, line)
	if len(r.lines) > r.max {
		r.lines = r.lines[len(r.lines)-r.max:]
	}
}

func (r *ringLog) String() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return strings.Join(r.lines, "\n")
}

func (r *ringLog) clear() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lines = nil
}

var (
	secretMu   sync.Mutex
	logAuthKey string
	bridgeLog  = newRingLog(maxLogLines)
)

func setLogSecret(secret string) {
	secretMu.Lock()
	logAuthKey = secret
	secretMu.Unlock()
}

func redactSecrets(s string) string {
	secretMu.Lock()
	key := logAuthKey
	secretMu.Unlock()
	if key != "" {
		s = strings.ReplaceAll(s, key, "tskey-REDACTED")
	}
	return tskeyPattern.ReplaceAllString(s, "tskey-REDACTED")
}

func logf(format string, args ...any) {
	line := fmt.Sprintf(format, args...)
	stamp := time.Now().Format("15:04:05.000")
	bridgeLog.add(stamp + " " + line)
}
