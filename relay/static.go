package main

// Serves the Flutter web build: SPA fallback to index.html, precompressed
// .gz files (made at image build time) or gzip on the fly, ETag/Last-Modified
// revalidation, and the cross-origin isolation headers skwasm's threads need.

import (
	"compress/gzip"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

type static struct {
	root string
}

func newStatic(root string) http.Handler { return &static{root: root} }

var typeByExt = map[string]string{
	".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
	".json": "application/json", ".wasm": "application/wasm", ".css": "text/css; charset=utf-8",
	".png": "image/png", ".ico": "image/x-icon", ".svg": "image/svg+xml", ".otf": "font/otf", ".ttf": "font/ttf",
	".woff2": "font/woff2", ".frag": "application/octet-stream", ".bin": "application/octet-stream",
	".symbols": "text/plain; charset=utf-8", ".txt": "text/plain; charset=utf-8",
}

func compressible(ct string) bool {
	return strings.HasPrefix(ct, "text/") || strings.HasPrefix(ct, "application/json") || ct == "application/wasm" ||
		ct == "font/ttf" || ct == "font/otf" || ct == "image/svg+xml" || ct == "application/octet-stream"
}

func cacheControl(p string) string {
	switch {
	case strings.HasPrefix(p, "/canvaskit/"), strings.HasPrefix(p, "/assets/fonts/"), strings.HasPrefix(p, "/assets/packages/"),
		strings.HasPrefix(p, "/icons/"), strings.HasPrefix(p, "/fonts/"):
		return "public, max-age=86400"
	}
	return "no-cache" // revalidate (ETag / Last-Modified): Flutter's main files aren't content-hashed
}

func (s *static) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && r.Method != "HEAD" {
		http.Error(w, "method not allowed", 405)
		return
	}
	h := w.Header()
	h.Set("Cross-Origin-Opener-Policy", "same-origin")
	h.Set("Cross-Origin-Embedder-Policy", "require-corp")
	h.Set("Cross-Origin-Resource-Policy", "same-origin")
	p := path.Clean("/" + r.URL.Path)
	if p == "/" {
		p = "/index.html"
	}
	file := filepath.Join(s.root, filepath.FromSlash(p))
	st, err := os.Stat(file)
	if err != nil || st.IsDir() {
		if strings.Contains(path.Base(p), ".") {
			http.NotFound(w, r)
			return
		}
		p = "/index.html" // SPA: deep links like /?install=owner/repo or /install
		file = filepath.Join(s.root, "index.html")
		if st, err = os.Stat(file); err != nil {
			http.NotFound(w, r)
			return
		}
	}
	ct := typeByExt[strings.ToLower(path.Ext(p))]
	if ct == "" {
		ct = mime.TypeByExtension(path.Ext(p))
	}
	if ct == "" {
		ct = "application/octet-stream"
	}
	h.Set("Content-Type", ct)
	h.Set("Cache-Control", cacheControl(p))
	h.Add("Vary", "Accept-Encoding")
	acceptsGzip := strings.Contains(r.Header.Get("Accept-Encoding"), "gzip")

	if acceptsGzip {
		if gst, err := os.Stat(file + ".gz"); err == nil && !gst.IsDir() && !gst.ModTime().Before(st.ModTime()) {
			f, err := os.Open(file + ".gz")
			if err == nil {
				defer f.Close()
				h.Set("Content-Encoding", "gzip")
				h.Set("ETag", fmt.Sprintf(`"%x-%x-gz"`, st.Size(), st.ModTime().UnixNano()))
				http.ServeContent(w, r, "", st.ModTime(), f)
				return
			}
		}
	}
	f, err := os.Open(file)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	if acceptsGzip && compressible(ct) && st.Size() > 1024 && r.Header.Get("Range") == "" {
		etag := fmt.Sprintf(`"%x-%x-gz"`, st.Size(), st.ModTime().UnixNano())
		h.Set("ETag", etag)
		if inm := r.Header.Get("If-None-Match"); inm != "" && strings.Contains(inm, etag) {
			w.WriteHeader(304)
			return
		}
		h.Set("Content-Encoding", "gzip")
		h.Set("Last-Modified", st.ModTime().UTC().Format(http.TimeFormat))
		w.WriteHeader(200)
		if r.Method == "HEAD" {
			return
		}
		gz, _ := gzip.NewWriterLevel(w, gzip.BestSpeed)
		io.Copy(gz, f)
		gz.Close()
		return
	}
	h.Set("ETag", fmt.Sprintf(`"%x-%x"`, st.Size(), st.ModTime().UnixNano()))
	http.ServeContent(w, r, "", st.ModTime(), f)
}
