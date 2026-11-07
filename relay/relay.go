package main

// The relay: plugin fetches (/relay), audio streams (/stream), cover art
// (/img), GitHub plugin downloads (/api/github/*), the plugin registry
// (/api/plugins), sign-in to the relay (/api/session), and the web app.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"
)

const version = "0.2.1"

type Config struct {
	Token          string   // RELAY_TOKEN: required on every API request when set
	Repos          []string // RELAY_REPOS: only these owner/repo may register (empty = any)
	MediaHosts     []string // RELAY_MEDIA_HOSTS: extra hosts /stream and /img may reach
	AllowUpload    bool     // RELAY_ALLOW_MANIFEST_UPLOAD: register zip-installed plugins without a token
	AllowPrivate   bool     // RELAY_ALLOW_PRIVATE: let requests reach private addresses (tests/dev only)
	StaticDir      string   // the Flutter web build
	SecureCookie   bool     // RELAY_SECURE_COOKIE: mark the session cookie Secure (behind https)
	MaxBody        int64    // largest /relay response body
	MaxRequestBody int64
}

type Server struct {
	cfg      Config
	reg      *Registry
	gh       *GitHub
	client   *http.Client // upstream, follows no redirects (we do, checking each hop)
	resolver *net.Resolver
	proxied  bool // upstream goes through an HTTP proxy (resolve-and-check before each request)
	fonts    *fontCache
	mux      *http.ServeMux
}

// newTransport builds the upstream transport. Without a proxy, every
// connection is dialled to an address checked to be public (after DNS, so a
// rebinding name cannot slip through). With a proxy (HTTPS_PROXY), the proxy
// connects; the relay resolves and checks the name before each request.
func newTransport(cfg Config, resolver *net.Resolver) (*http.Transport, bool) {
	proxyFn := http.ProxyFromEnvironment
	probe, _ := http.NewRequest("GET", "https://example.com/", nil)
	pu, _ := proxyFn(probe)
	proxied := pu != nil
	d := &net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}
	t := &http.Transport{
		Proxy:                 proxyFn,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          64,
		IdleConnTimeout:       60 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
	}
	t.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
		if cfg.AllowPrivate || proxied {
			return d.DialContext(ctx, network, addr)
		}
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			return nil, err
		}
		addrs, err := resolvePublic(ctx, resolver, host)
		if err != nil {
			return nil, err
		}
		var last error
		for _, a := range addrs {
			c, err := d.DialContext(ctx, network, net.JoinHostPort(a.String(), port))
			if err == nil {
				return c, nil
			}
			last = err
		}
		return nil, last
	}
	return t, proxied
}

func NewServer(cfg Config, reg *Registry, rt http.RoundTripper, proxied bool) *Server {
	if cfg.MaxBody == 0 {
		cfg.MaxBody = 64 << 20
	}
	if cfg.MaxRequestBody == 0 {
		cfg.MaxRequestBody = 16 << 20
	}
	s := &Server{cfg: cfg, reg: reg, resolver: net.DefaultResolver, proxied: proxied}
	noRedirect := func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	s.client = &http.Client{Transport: rt, CheckRedirect: noRedirect, Timeout: 0}
	s.gh = &GitHub{Client: &http.Client{Transport: rt, Timeout: 2 * time.Minute}, Codeload: "https://codeload.github.com", Raw: "https://raw.githubusercontent.com", TTL: 10 * time.Minute}
	s.fonts = &fontCache{client: &http.Client{Transport: rt, Timeout: time.Minute}, base: "https://fonts.gstatic.com/s/"}
	m := http.NewServeMux()
	m.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "ok\n") })
	m.HandleFunc("/api/status", s.status)
	m.HandleFunc("/api/session", s.session)
	m.HandleFunc("/api/plugins", s.auth(s.plugins))
	m.HandleFunc("/api/plugins/", s.auth(s.plugins))
	m.HandleFunc("/api/github/zip", s.auth(s.githubZip))
	m.HandleFunc("/api/github/manifest", s.auth(s.githubManifest))
	m.HandleFunc("/api/log", s.auth(s.clientLog))
	m.HandleFunc("/relay", s.auth(s.relay))
	m.HandleFunc("/stream", s.auth(s.media(false)))
	m.HandleFunc("/img", s.auth(s.media(true)))
	m.HandleFunc("/gfonts/", s.fonts.serve)
	m.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) { jsonError(w, 404, "not_found", "no such endpoint") })
	if cfg.StaticDir != "" {
		m.Handle("/", newStatic(cfg.StaticDir))
	}
	s.mux = m
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h := w.Header()
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	s.mux.ServeHTTP(w, r)
}

// ---------- auth ----------

const cookieName = "mygo_relay"

// sessionValue is what the session cookie holds: an HMAC of the token, so the
// token itself never sits in a cookie and changing RELAY_TOKEN signs everyone out.
func (s *Server) sessionValue() string {
	m := hmac.New(sha256.New, []byte(s.cfg.Token))
	m.Write([]byte("mygo-relay-session-v1"))
	return hex.EncodeToString(m.Sum(nil))
}

func (s *Server) authenticated(r *http.Request) bool {
	if s.cfg.Token == "" {
		return true
	}
	if a := r.Header.Get("Authorization"); strings.HasPrefix(a, "Bearer ") {
		if subtle.ConstantTimeCompare([]byte(strings.TrimPrefix(a, "Bearer ")), []byte(s.cfg.Token)) == 1 {
			return true
		}
	}
	if c, err := r.Cookie(cookieName); err == nil {
		if subtle.ConstantTimeCompare([]byte(c.Value), []byte(s.sessionValue())) == 1 {
			return true
		}
	}
	return false
}

func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.authenticated(r) {
			jsonError(w, 401, "token", "the relay needs its access token")
			return
		}
		next(w, r)
	}
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	ids := []string{}
	authed := s.authenticated(r)
	if authed {
		for _, e := range s.reg.List() {
			ids = append(ids, e.ID)
		}
	}
	writeJSON(w, 200, map[string]any{
		"version":        version,
		"tokenRequired":  s.cfg.Token != "",
		"authenticated":  authed,
		"plugins":        ids,
		"manifestUpload": s.cfg.AllowUpload || s.cfg.Token != "",
	})
}

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "POST":
		var body struct {
			Token string `json:"token"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&body); err != nil {
			jsonError(w, 400, "bad_request", "expected {\"token\": ...}")
			return
		}
		if s.cfg.Token == "" {
			writeJSON(w, 200, map[string]any{"ok": true})
			return
		}
		if subtle.ConstantTimeCompare([]byte(body.Token), []byte(s.cfg.Token)) != 1 {
			time.Sleep(500 * time.Millisecond) // slow down guessing
			jsonError(w, 401, "token", "wrong token")
			return
		}
		http.SetCookie(w, &http.Cookie{Name: cookieName, Value: s.sessionValue(), Path: "/", HttpOnly: true,
			SameSite: http.SameSiteStrictMode, Secure: s.cfg.SecureCookie || r.TLS != nil, MaxAge: 400 * 24 * 3600})
		writeJSON(w, 200, map[string]any{"ok": true})
	case "DELETE":
		http.SetCookie(w, &http.Cookie{Name: cookieName, Value: "", Path: "/", HttpOnly: true, MaxAge: -1})
		writeJSON(w, 200, map[string]any{"ok": true})
	default:
		jsonError(w, 405, "method", "POST or DELETE")
	}
}

// ---------- registry API ----------

func (s *Server) repoAllowed(repo string) bool {
	if len(s.cfg.Repos) == 0 {
		return true
	}
	for _, r := range s.cfg.Repos {
		if strings.EqualFold(r, repo) {
			return true
		}
	}
	return false
}

func (s *Server) plugins(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(strings.TrimPrefix(r.URL.Path, "/api/plugins"), "/")
	switch {
	case r.Method == "GET" && id == "":
		writeJSON(w, 200, s.reg.List())
	case r.Method == "GET":
		e, ok := s.reg.Get(id)
		if !ok {
			jsonError(w, 404, "not_found", "plugin "+id+" is not registered")
			return
		}
		writeJSON(w, 200, e)
	case r.Method == "DELETE" && id != "":
		if err := s.reg.Delete(id); err != nil {
			jsonError(w, 500, "storage", err.Error())
			return
		}
		writeJSON(w, 200, map[string]any{"ok": true})
	case r.Method == "POST" && id == "":
		var body struct {
			Kind     string          `json:"kind"`
			Repo     string          `json:"repo"`
			Branch   string          `json:"branch"`
			Manifest json.RawMessage `json:"manifest"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&body); err != nil {
			jsonError(w, 400, "bad_request", "bad JSON")
			return
		}
		var e Entry
		var err error
		switch body.Kind {
		case "github":
			if !s.repoAllowed(body.Repo) {
				jsonError(w, 403, "repo", "this relay does not serve "+body.Repo)
				return
			}
			data, branch, status, zerr := s.gh.Zip(body.Repo, body.Branch)
			if zerr != nil {
				jsonError(w, status, "github", zerr.Error())
				return
			}
			mb, merr := manifestFromZip(data)
			if merr != nil {
				jsonError(w, 400, "manifest", merr.Error())
				return
			}
			e, err = entryFromManifest(mb)
			e.Source, e.Repo, e.Branch = "github", body.Repo, branch
		case "manifest":
			if len(s.cfg.Repos) > 0 || !(s.cfg.AllowUpload || s.cfg.Token != "") {
				jsonError(w, 403, "upload", "this relay only registers plugins from GitHub")
				return
			}
			e, err = entryFromManifest(body.Manifest)
			e.Source = "manifest"
		default:
			jsonError(w, 400, "bad_request", `kind must be "github" or "manifest"`)
			return
		}
		if err != nil {
			jsonError(w, 400, "manifest", err.Error())
			return
		}
		if old, ok := s.reg.Get(e.ID); ok && old.Source == "github" && e.Source == "manifest" {
			// An upload doesn't replace what GitHub vouched for.
			writeJSON(w, 200, old)
			return
		}
		e.Registered = time.Now().Unix()
		if err := s.reg.Put(e); err != nil {
			jsonError(w, 500, "storage", err.Error())
			return
		}
		log.Printf("registered plugin %s (%s %s) hosts=%v", e.ID, e.Source, e.Repo, e.Network)
		writeJSON(w, 200, e)
	default:
		jsonError(w, 405, "method", "unsupported")
	}
}

func (s *Server) githubZip(w http.ResponseWriter, r *http.Request) {
	repo := r.URL.Query().Get("repo")
	if !s.repoAllowed(repo) {
		jsonError(w, 403, "repo", "this relay does not serve "+repo)
		return
	}
	data, branch, status, err := s.gh.Zip(repo, r.URL.Query().Get("branch"))
	if err != nil {
		jsonError(w, status, "github", err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("X-Relay-Branch", branch)
	w.Header().Set("Cache-Control", "no-store")
	w.Write(data)
}

func (s *Server) githubManifest(w http.ResponseWriter, r *http.Request) {
	repo := r.URL.Query().Get("repo")
	if !s.repoAllowed(repo) {
		jsonError(w, 403, "repo", "this relay does not serve "+repo)
		return
	}
	b, err := s.gh.Manifest(repo, r.URL.Query().Get("branch"))
	if err != nil {
		jsonError(w, 502, "github", err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(b)
}

// ---------- upstream ----------

// hopHeaders are never forwarded either way.
var hopHeaders = map[string]bool{
	"connection": true, "keep-alive": true, "proxy-authenticate": true, "proxy-authorization": true,
	"proxy-connection": true, "te": true, "trailer": true, "transfer-encoding": true, "upgrade": true,
	"host": true, "content-length": true,
}

// checkTarget validates a URL a request wants to reach and, behind a proxy,
// resolves its host and checks the addresses.
func (s *Server) checkTarget(ctx context.Context, u *url.URL) error {
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("not a web address: %s", u.Scheme)
	}
	if u.User != nil {
		return errors.New("credentials in URLs are not relayed")
	}
	host := u.Hostname()
	if s.cfg.AllowPrivate {
		return nil
	}
	if err := checkHostName(host); err != nil {
		return err
	}
	if s.proxied {
		if _, err := resolvePublic(ctx, s.resolver, host); err != nil {
			return err
		}
	}
	return nil
}

type hostRule func(host string) bool

// do sends a request, following redirects itself (when follow is set) and
// checking every hop against the rule. It answers the last response, the
// final URL and whether a redirect was followed.
func (s *Server) do(ctx context.Context, method string, u *url.URL, hdr http.Header, body []byte, follow bool, allowed hostRule) (*http.Response, *url.URL, bool, error) {
	redirected := false
	for hop := 0; ; hop++ {
		if !allowed(u.Hostname()) {
			return nil, u, redirected, &relayErr{403, "host", fmt.Sprintf("webapi: host %s is not allowed", strings.ToLower(u.Hostname()))}
		}
		if err := s.checkTarget(ctx, u); err != nil {
			return nil, u, redirected, &relayErr{403, "host", err.Error()}
		}
		var rb io.Reader
		if body != nil {
			rb = strings.NewReader(string(body))
		}
		req, err := http.NewRequestWithContext(ctx, method, u.String(), rb)
		if err != nil {
			return nil, u, redirected, &relayErr{400, "bad_request", err.Error()}
		}
		for k, vs := range hdr {
			for _, v := range vs {
				req.Header.Add(k, v)
			}
		}
		if req.Header.Get("User-Agent") == "" {
			req.Header.Set("User-Agent", "") // Go's default UA would identify the relay
		}
		res, err := s.client.Do(req)
		if err != nil {
			return nil, u, redirected, &relayErr{502, "upstream", "fetch failed: " + err.Error()}
		}
		loc := res.Header.Get("Location")
		if follow && loc != "" && (res.StatusCode == 301 || res.StatusCode == 302 || res.StatusCode == 303 || res.StatusCode == 307 || res.StatusCode == 308) {
			io.Copy(io.Discard, io.LimitReader(res.Body, 1<<16))
			res.Body.Close()
			if hop >= 20 {
				return nil, u, redirected, &relayErr{502, "upstream", "fetch: too many redirects"}
			}
			next, err := u.Parse(loc)
			if err != nil {
				return nil, u, redirected, &relayErr{502, "upstream", "fetch: bad redirect"}
			}
			if res.StatusCode == 303 || ((res.StatusCode == 301 || res.StatusCode == 302) && method == "POST") {
				method, body = "GET", nil
				hdr.Del("Content-Type")
			}
			if next.Host != u.Host {
				hdr.Del("Authorization")
				hdr.Del("Cookie")
			}
			u, redirected = next, true
			continue
		}
		return res, u, redirected, nil
	}
}

type relayErr struct {
	status int
	code   string
	msg    string
}

func (e *relayErr) Error() string { return e.msg }

func writeRelayErr(w http.ResponseWriter, err error) {
	var re *relayErr
	if errors.As(err, &re) {
		jsonError(w, re.status, re.code, re.msg)
		return
	}
	jsonError(w, 502, "upstream", err.Error())
}

// decodeHeaderList reads [[name, value], ...] from base64(JSON).
func decodeHeaderList(s string) (http.Header, error) {
	h := http.Header{}
	if s == "" {
		return h, nil
	}
	raw, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		if raw, err = base64.RawURLEncoding.DecodeString(s); err != nil {
			return nil, errors.New("headers: not base64")
		}
	}
	var list [][]string
	if err := json.Unmarshal(raw, &list); err != nil {
		return nil, errors.New("headers: expected [[name, value], ...]")
	}
	for _, kv := range list {
		if len(kv) != 2 {
			return nil, errors.New("headers: expected [[name, value], ...]")
		}
		name := strings.TrimSpace(kv[0])
		if name == "" || strings.ContainsAny(name, " :\r\n") || strings.ContainsAny(kv[1], "\r\n") {
			return nil, fmt.Errorf("headers: bad header %q", name)
		}
		l := strings.ToLower(name)
		if hopHeaders[l] || l == "accept-encoding" || strings.HasPrefix(l, "x-relay-") {
			continue // the transport negotiates (and undoes) compression itself
		}
		h.Add(name, kv[1])
	}
	return h, nil
}

func encodeHeaderList(h http.Header) string {
	list := [][]string{}
	for k, vs := range h {
		l := strings.ToLower(k)
		if hopHeaders[l] && l != "content-length" {
			continue
		}
		for _, v := range vs {
			list = append(list, []string{l, v})
		}
	}
	b, _ := json.Marshal(list)
	return base64.StdEncoding.EncodeToString(b)
}

// relay: one plugin fetch. The request names the plugin and URL in the query
// (?plugin=<id>&url=<url>), the method in X-Relay-Method, the plugin's
// headers (any, including Cookie, User-Agent, Referer, which a browser won't
// let a page set) as base64 JSON [[name, value], ...] in X-Relay-Headers, the
// redirect mode in X-Relay-Redirect (follow | manual | error); the body is the
// request body. The answer is 200 with the upstream's status, final URL and
// headers (Set-Cookie included) in X-Relay-Status / -Status-Text / -Url /
// -Redirected / -Headers and its body as the body. Failures of the relay
// itself are JSON with X-Relay-Error.
func (s *Server) relay(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" && r.Method != "GET" {
		jsonError(w, 405, "method", "use POST (or GET)")
		return
	}
	q := r.URL.Query()
	pid := q.Get("plugin")
	if pid == "" {
		pid = r.Header.Get("X-Relay-Plugin")
	}
	e, ok := s.reg.Get(pid)
	if !ok {
		jsonError(w, 403, "plugin", fmt.Sprintf("plugin %q is not registered with the relay", pid))
		return
	}
	raw := q.Get("url")
	if raw == "" {
		raw = r.Header.Get("X-Relay-Url")
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		jsonError(w, 400, "bad_request", "fetch: not a web address: "+raw)
		return
	}
	method := strings.ToUpper(r.Header.Get("X-Relay-Method"))
	if method == "" {
		method = r.Method
	}
	if !validMethod(method) {
		jsonError(w, 400, "bad_request", "bad method")
		return
	}
	hdr, err := decodeHeaderList(r.Header.Get("X-Relay-Headers"))
	if err != nil {
		jsonError(w, 400, "bad_request", err.Error())
		return
	}
	var body []byte
	if r.Method == "POST" && method != "GET" && method != "HEAD" {
		body, err = io.ReadAll(io.LimitReader(r.Body, s.cfg.MaxRequestBody+1))
		if err != nil {
			jsonError(w, 400, "bad_request", err.Error())
			return
		}
		if int64(len(body)) > s.cfg.MaxRequestBody {
			jsonError(w, 413, "too_big", "request body too big")
			return
		}
	}
	mode := r.Header.Get("X-Relay-Redirect")
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Minute)
	defer cancel()
	res, final, redirected, err := s.do(ctx, method, u, hdr, body, mode != "manual" && mode != "error", func(h string) bool { return hostMatches(e.Network, h) })
	if err != nil {
		writeRelayErr(w, err)
		return
	}
	defer res.Body.Close()
	if mode == "error" && res.StatusCode >= 300 && res.StatusCode < 400 && res.Header.Get("Location") != "" {
		jsonError(w, 502, "upstream", "fetch: redirect not allowed")
		return
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, s.cfg.MaxBody+1))
	if err != nil {
		jsonError(w, 502, "upstream", "fetch failed: "+err.Error())
		return
	}
	if int64(len(data)) > s.cfg.MaxBody {
		jsonError(w, 502, "too_big", "response too big for the relay")
		return
	}
	h := w.Header()
	h.Set("Content-Type", "application/octet-stream")
	h.Set("Cache-Control", "no-store")
	h.Set("X-Relay-Status", strconv.Itoa(res.StatusCode))
	h.Set("X-Relay-Status-Text", strings.TrimSpace(strings.TrimPrefix(res.Status, strconv.Itoa(res.StatusCode))))
	h.Set("X-Relay-Url", final.String())
	if redirected {
		h.Set("X-Relay-Redirected", "1")
	}
	rh := res.Header.Clone()
	if res.Uncompressed {
		rh.Del("Content-Encoding")
	}
	rh.Set("Content-Length", strconv.Itoa(len(data)))
	h.Set("X-Relay-Headers", encodeHeaderList(rh))
	h.Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(200)
	w.Write(data)
}

func validMethod(m string) bool {
	switch m {
	case "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS":
		return true
	}
	return false
}

// ---------- media ----------

var audioExt = map[string]string{
	".flac": "audio/flac", ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".mp4": "audio/mp4", ".aac": "audio/aac",
	".ogg": "audio/ogg", ".opus": "audio/ogg", ".wav": "audio/wav", ".webm": "audio/webm",
}

// mediaType decides the Content-Type the browser gets, or "" when the answer
// isn't media (so /stream and /img can't be used to fetch pages or APIs).
func mediaType(upstream, urlPath string, image bool) string {
	mt, _, _ := mime.ParseMediaType(upstream)
	mt = strings.ToLower(mt)
	if image {
		if strings.HasPrefix(mt, "image/") && mt != "image/svg+xml" {
			return mt
		}
		if mt == "" || mt == "application/octet-stream" || mt == "binary/octet-stream" {
			switch strings.ToLower(path.Ext(urlPath)) {
			case ".jpg", ".jpeg":
				return "image/jpeg"
			case ".png":
				return "image/png"
			case ".webp":
				return "image/webp"
			case ".gif":
				return "image/gif"
			}
		}
		return ""
	}
	byExt := audioExt[strings.ToLower(path.Ext(urlPath))]
	switch {
	case strings.HasPrefix(mt, "audio/") || strings.HasPrefix(mt, "video/") || mt == "application/ogg":
		if (mt == "audio/x-flac" || mt == "audio/x-mpeg") && byExt != "" {
			return byExt
		}
		return mt
	case mt == "" || mt == "application/octet-stream" || mt == "binary/octet-stream" || mt == "application/x-flac" || mt == "application/x-mpeg":
		if byExt != "" {
			return byExt
		}
		return "application/octet-stream"
	}
	return ""
}

// media serves /stream (audio, Range passed through) and /img (cover art):
// GET ?url=<url>[&h=<base64 JSON headers>]. Hosts: those of registered plugins
// and their registrable domains, plus RELAY_MEDIA_HOSTS; answers must be
// audio (or an octet stream) / images. The browser's own cookies never go
// upstream; the plugin's stream headers (h) do.
func (s *Server) media(image bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" && r.Method != "HEAD" {
			jsonError(w, 405, "method", "GET")
			return
		}
		q := r.URL.Query()
		u, err := url.Parse(q.Get("url"))
		if err != nil || u.Host == "" {
			jsonError(w, 400, "bad_request", "not a web address")
			return
		}
		var hdr http.Header
		if image {
			hdr = http.Header{}
		} else if hdr, err = decodeHeaderList(q.Get("h")); err != nil {
			jsonError(w, 400, "bad_request", err.Error())
			return
		}
		for _, k := range []string{"Range", "If-Range", "If-None-Match", "If-Modified-Since"} {
			if v := r.Header.Get(k); v != "" {
				hdr.Set(k, v)
			}
		}
		var patterns []string
		if pid := q.Get("plugin"); pid != "" {
			e, ok := s.reg.Get(pid)
			if !ok {
				jsonError(w, 403, "plugin", fmt.Sprintf("plugin %q is not registered with the relay", pid))
				return
			}
			patterns = e.Network
		} else {
			patterns = s.reg.AllPatterns()
		}
		rule := func(h string) bool { return mediaHostAllowed(patterns, s.cfg.MediaHosts, h) }
		if image && s.cfg.Token != "" {
			// Cover art lives on CDNs no manifest lists (Kugou's is kgimg.com).
			// Behind a token the relay is a private service, the answer must be
			// an image, and checkTarget still keeps requests off private
			// addresses, so any public host is fine for /img.
			rule = func(string) bool { return true }
		}
		res, final, _, err := s.do(r.Context(), r.Method, u, hdr, nil, true, rule)
		if err != nil {
			writeRelayErr(w, err)
			return
		}
		defer res.Body.Close()
		if res.StatusCode == 304 {
			w.WriteHeader(304)
			return
		}
		if res.StatusCode >= 400 {
			io.Copy(io.Discard, io.LimitReader(res.Body, 1<<16))
			jsonError(w, res.StatusCode, "upstream", fmt.Sprintf("upstream answered %d", res.StatusCode))
			return
		}
		ct := mediaType(res.Header.Get("Content-Type"), final.Path, image)
		if ct == "" {
			jsonError(w, 415, "not_media", "the answer is not "+map[bool]string{true: "an image", false: "audio"}[image])
			return
		}
		h := w.Header()
		h.Set("Content-Type", ct)
		for _, k := range []string{"Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag"} {
			if v := res.Header.Get(k); v != "" && !(k == "Content-Length" && res.Uncompressed) {
				h.Set(k, v)
			}
		}
		if image {
			h.Set("Cache-Control", "private, max-age=86400")
		} else {
			h.Set("Cache-Control", "private, no-transform, max-age=600")
			if h.Get("Accept-Ranges") == "" && res.StatusCode == 206 {
				h.Set("Accept-Ranges", "bytes")
			}
		}
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		w.WriteHeader(res.StatusCode)
		if r.Method == "HEAD" {
			return
		}
		flushCopy(w, res.Body)
	}
}

func flushCopy(w http.ResponseWriter, r io.Reader) {
	f, _ := w.(http.Flusher)
	buf := make([]byte, 64<<10)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return
			}
			if f != nil {
				f.Flush()
			}
		}
		if err != nil {
			return
		}
	}
}

// ---------- helpers ----------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func jsonError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("X-Relay-Error", "1")
	writeJSON(w, status, map[string]string{"error": msg, "code": code})
}

// clientLog writes what the app reports about a failure (an install that
// didn't finish, say) to the relay's log, so a problem on a phone, where
// there is no console to read, can be seen on the server. Small, plain text,
// one line per entry; nothing is stored.
func (s *Server) clientLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		jsonError(w, 405, "method", "POST")
		return
	}
	var body struct {
		Kind    string `json:"kind"`
		Message string `json:"message"`
		Context string `json:"context"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 8192)).Decode(&body); err != nil {
		jsonError(w, 400, "bad_request", "expected {\"kind\", \"message\"}")
		return
	}
	clean := func(v string, n int) string {
		v = strings.Map(func(c rune) rune {
			if c < 0x20 || c == 0x7f {
				return ' '
			}
			return c
		}, v)
		if len(v) > n {
			v = v[:n] + "…"
		}
		return v
	}
	log.Printf("client %s: %s [%s] ua=%q", clean(body.Kind, 40), clean(body.Message, 1500), clean(body.Context, 500), clean(r.UserAgent(), 200))
	writeJSON(w, 200, map[string]any{"ok": true})
}
