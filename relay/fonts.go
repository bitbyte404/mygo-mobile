package main

// /gfonts/<path>: Flutter web's fallback fonts (Noto, split in subsets, the
// CJK glyphs the UI needs) fetched from fonts.gstatic.com/s/<path> once and
// kept in memory, so the page itself only talks to the relay's origin (needed
// under Cross-Origin-Embedder-Policy, and kinder where gstatic is slow).
// Fixed upstream host and a strict path pattern: not a general proxy.

import (
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
)

type fontCache struct {
	client *http.Client
	base   string
	mu     sync.Mutex
	files  map[string][]byte
	size   int
}

var fontPath = regexp.MustCompile(`^[a-z0-9_-]+/v[0-9]+/[A-Za-z0-9_.-]+\.(woff2|woff|ttf|otf)$`)

const fontCacheMax = 256 << 20

func (c *fontCache) serve(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(r.URL.Path, "/gfonts/")
	if r.Method != "GET" || !fontPath.MatchString(p) || strings.Contains(p, "..") {
		http.NotFound(w, r)
		return
	}
	c.mu.Lock()
	b, ok := c.files[p]
	c.mu.Unlock()
	if !ok {
		res, err := c.client.Get(c.base + p)
		if err != nil {
			http.Error(w, "font fetch failed", 502)
			return
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			http.Error(w, "font not found", res.StatusCode)
			return
		}
		b, err = io.ReadAll(io.LimitReader(res.Body, 16<<20))
		if err != nil {
			http.Error(w, "font fetch failed", 502)
			return
		}
		c.mu.Lock()
		if c.files == nil {
			c.files = map[string][]byte{}
		}
		if c.size+len(b) < fontCacheMax {
			c.files[p] = b
			c.size += len(b)
		}
		c.mu.Unlock()
	}
	ct := "font/woff2"
	switch {
	case strings.HasSuffix(p, ".ttf"):
		ct = "font/ttf"
	case strings.HasSuffix(p, ".otf"):
		ct = "font/otf"
	case strings.HasSuffix(p, ".woff"):
		ct = "font/woff"
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Cache-Control", "public, max-age=2592000, immutable")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Write(b)
}
