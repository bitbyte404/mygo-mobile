package main

// Host rules: what a plugin may declare, which hosts a request may reach, and
// the network-level guard against reaching the relay's own network (SSRF).

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"strings"
)

// validPattern says whether a permissions.network entry is acceptable for the
// relay: an exact host name ("gateway.kugou.com") or a wildcard over a
// registrable domain ("*.kugou.com"). The desktop app also accepts "*" (any
// host); the relay refuses it, since that would make it an open proxy.
func validPattern(p string) error {
	p = strings.ToLower(strings.TrimSpace(p))
	if p == "" {
		return errors.New("empty host")
	}
	if p == "*" {
		return errors.New(`"*" (any host) is not allowed through the relay`)
	}
	h := strings.TrimPrefix(p, "*.")
	if strings.Contains(h, "*") {
		return fmt.Errorf("bad wildcard %q", p)
	}
	if strings.HasPrefix(p, "*.") && isPublicSuffix(h) {
		return fmt.Errorf("wildcard %q is too broad", p)
	}
	if err := checkHostName(h); err != nil {
		return err
	}
	return nil
}

// checkHostName refuses IP literals and names that only make sense inside a
// private network. It does not resolve anything.
func checkHostName(h string) error {
	h = strings.ToLower(strings.TrimSuffix(h, "."))
	if h == "" {
		return errors.New("empty host")
	}
	if _, err := netip.ParseAddr(strings.Trim(h, "[]")); err == nil {
		return fmt.Errorf("IP address hosts are not allowed: %s", h)
	}
	if h == "localhost" || !strings.Contains(h, ".") {
		return fmt.Errorf("host %s is not a public name", h)
	}
	for _, s := range []string{".localhost", ".local", ".internal", ".lan", ".home.arpa", ".intranet", ".corp"} {
		if strings.HasSuffix(h, s) {
			return fmt.Errorf("host %s is not a public name", h)
		}
	}
	for _, c := range h {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '.') {
			return fmt.Errorf("bad host name %q", h)
		}
	}
	return nil
}

// hostMatches is the desktop's webapi.AllowHosts rule: exact names or *.suffix.
// ("*" never reaches here: validPattern refuses it.)
func hostMatches(patterns []string, host string) bool {
	h := strings.ToLower(strings.TrimSuffix(host, "."))
	for _, p := range patterns {
		p = strings.ToLower(p)
		if strings.HasPrefix(p, "*.") {
			if strings.HasSuffix(h, p[1:]) {
				return true
			}
		} else if p == h {
			return true
		}
	}
	return false
}

// Second-level labels under which registrations happen (an approximation of
// the public suffix list, enough for the CDNs music services use).
var secondLevel = map[string]bool{
	"com.cn": true, "net.cn": true, "org.cn": true, "gov.cn": true, "edu.cn": true,
	"com.hk": true, "com.tw": true, "com.sg": true, "com.au": true, "net.au": true,
	"co.uk": true, "org.uk": true, "ac.uk": true, "co.jp": true, "ne.jp": true, "or.jp": true,
	"co.kr": true, "com.br": true, "co.nz": true, "co.in": true,
}

func isPublicSuffix(h string) bool {
	return !strings.Contains(h, ".") || secondLevel[h]
}

// registrableDomain approximates eTLD+1: "fs.youthandroid2.kugou.com" →
// "kugou.com", "a.b.example.com.cn" → "example.com.cn".
func registrableDomain(host string) string {
	h := strings.ToLower(strings.TrimSuffix(host, "."))
	parts := strings.Split(h, ".")
	if len(parts) <= 2 {
		return h
	}
	n := 2
	if secondLevel[strings.Join(parts[len(parts)-2:], ".")] {
		n = 3
	}
	if len(parts) < n {
		return h
	}
	return strings.Join(parts[len(parts)-n:], ".")
}

// mediaHostAllowed: a stream or image host is allowed when a plugin may reach
// it directly, when it is under the same registrable domain as a host a
// plugin may reach (CDNs: kugou's streams come from fs.*.kugou.com while its
// API is gateway.kugou.com), or when the operator listed it.
func mediaHostAllowed(patterns, extra []string, host string) bool {
	if hostMatches(patterns, host) || hostMatches(extra, host) {
		return true
	}
	rd := registrableDomain(host)
	if isPublicSuffix(rd) {
		return false
	}
	for _, p := range patterns {
		if registrableDomain(strings.TrimPrefix(strings.ToLower(p), "*.")) == rd {
			return true
		}
	}
	return false
}

var blockedPrefixes = func() []netip.Prefix {
	var out []netip.Prefix
	for _, s := range []string{
		"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
		"192.0.0.0/24", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4",
		"::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "64:ff9b::/96",
	} {
		out = append(out, netip.MustParsePrefix(s))
	}
	return out
}()

// publicIP says whether an address is on the public internet.
func publicIP(a netip.Addr) bool {
	a = a.Unmap()
	if !a.IsValid() || a.IsLoopback() || a.IsPrivate() || a.IsLinkLocalUnicast() || a.IsMulticast() || a.IsUnspecified() {
		return false
	}
	for _, p := range blockedPrefixes {
		if p.Contains(a) {
			return false
		}
	}
	return true
}

// resolvePublic resolves host and fails unless every address is public.
func resolvePublic(ctx context.Context, r *net.Resolver, host string) ([]netip.Addr, error) {
	if a, err := netip.ParseAddr(strings.Trim(host, "[]")); err == nil {
		if !publicIP(a) {
			return nil, fmt.Errorf("address %s is not public", a)
		}
		return []netip.Addr{a}, nil
	}
	addrs, err := r.LookupNetIP(ctx, "ip", host)
	if err != nil {
		return nil, err
	}
	if len(addrs) == 0 {
		return nil, fmt.Errorf("no address for %s", host)
	}
	for _, a := range addrs {
		if !publicIP(a) {
			return nil, fmt.Errorf("%s resolves to a non-public address (%s)", host, a)
		}
	}
	return addrs, nil
}
