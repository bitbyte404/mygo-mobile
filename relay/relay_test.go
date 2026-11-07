package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// upstreamTransport sends every request, whatever its host, to the test
// upstream server, so tests can use public-looking host names.
// http:// goes to the plain server, https:// to a TLS one with the same handler.
func upstreamTransport(t *testing.T, upstream *httptest.Server, tlsUp *httptest.Server) http.RoundTripper {
	addr := strings.TrimPrefix(upstream.URL, "http://")
	tlsAddr := strings.TrimPrefix(tlsUp.URL, "https://")
	return &http.Transport{
		DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, addr)
		},
		DialTLSContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return tls.DialWithDialer(&net.Dialer{}, network, tlsAddr, &tls.Config{InsecureSkipVerify: true})
		},
	}
}

func newTestServer(t *testing.T, cfg Config, upstream http.Handler) (*Server, *httptest.Server) {
	t.Helper()
	up := httptest.NewServer(upstream)
	t.Cleanup(up.Close)
	tlsUp := httptest.NewTLSServer(upstream)
	t.Cleanup(tlsUp.Close)
	cfg.AllowPrivate = true // the upstream is on 127.0.0.1
	reg, _ := NewRegistry("")
	s := NewServer(cfg, reg, upstreamTransport(t, up, tlsUp), false)
	return s, up
}

func register(t *testing.T, s *Server, id string, hosts ...string) {
	t.Helper()
	b, _ := json.Marshal(map[string]any{"id": id, "permissions": map[string]any{"network": hosts}})
	e, err := entryFromManifest(b)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.reg.Put(e); err != nil {
		t.Fatal(err)
	}
}

func b64(v any) string {
	b, _ := json.Marshal(v)
	return base64.StdEncoding.EncodeToString(b)
}

func relayReq(method, target, plugin string, headers [][]string, body string) *http.Request {
	r := httptest.NewRequest("POST", "/relay?plugin="+url.QueryEscape(plugin)+"&url="+url.QueryEscape(target), strings.NewReader(body))
	r.Header.Set("X-Relay-Method", method)
	if headers != nil {
		r.Header.Set("X-Relay-Headers", b64(headers))
	}
	return r
}

func decodeList(t *testing.T, s string) [][]string {
	t.Helper()
	raw, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	var l [][]string
	json.Unmarshal(raw, &l)
	return l
}

// ---------- allowlist ----------

func TestValidPattern(t *testing.T) {
	ok := []string{"gateway.kugou.com", "*.kugou.com", "api.example.com.cn", "*.example.co.uk"}
	bad := []string{"*", "*.com", "*.com.cn", "*.co.uk", "localhost", "127.0.0.1", "[::1]", "10.0.0.1", "foo.local", "intranet", "a.*.b.com", "svc.internal", ""}
	for _, p := range ok {
		if err := validPattern(p); err != nil {
			t.Errorf("%s: unexpected %v", p, err)
		}
	}
	for _, p := range bad {
		if err := validPattern(p); err == nil {
			t.Errorf("%s: accepted", p)
		}
	}
}

func TestHostMatchesAndMedia(t *testing.T) {
	pats := []string{"gateway.kugou.com", "*.example.org"}
	cases := map[string]bool{"gateway.kugou.com": true, "GATEWAY.kugou.com.": true, "evil.com": false, "kugou.com": false,
		"a.example.org": true, "example.org": false, "gateway.kugou.com.evil.com": false}
	for h, want := range cases {
		if got := hostMatches(pats, h); got != want {
			t.Errorf("hostMatches(%s)=%v", h, got)
		}
	}
	media := map[string]bool{"fs.youthandroid2.kugou.com": true, "imge.kugou.com": true, "kugou.com.evil.net": false, "evil.com": false, "cdn.other.net": true}
	for h, want := range media {
		if got := mediaHostAllowed(pats, []string{"cdn.other.net"}, h); got != want {
			t.Errorf("mediaHostAllowed(%s)=%v", h, got)
		}
	}
	if registrableDomain("a.b.example.com.cn") != "example.com.cn" || registrableDomain("x.kugou.com") != "kugou.com" {
		t.Error("registrableDomain")
	}
}

func TestManifestRejectsAnyHost(t *testing.T) {
	if _, err := entryFromManifest([]byte(`{"id":"x","permissions":{"network":["*"]}}`)); err == nil {
		t.Fatal(`"*" accepted`)
	}
	if _, err := entryFromManifest([]byte(`{"id":"../x","permissions":{"network":[]}}`)); err == nil {
		t.Fatal("bad id accepted")
	}
}

func TestRelayRefusesUnregisteredPluginAndHost(t *testing.T) {
	s, _ := newTestServer(t, Config{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "secret") }))
	register(t, s, "p", "api.example.com")

	w := httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("GET", "https://api.example.com/x", "nope", nil, ""))
	if w.Code != 403 || w.Header().Get("X-Relay-Error") == "" {
		t.Fatalf("unregistered plugin: %d %s", w.Code, w.Body)
	}
	w = httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("GET", "https://evil.example.net/x", "p", nil, ""))
	if w.Code != 403 || !strings.Contains(w.Body.String(), "not allowed") {
		t.Fatalf("other host: %d %s", w.Code, w.Body)
	}
	w = httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("GET", "file:///etc/passwd", "p", nil, ""))
	if w.Code < 400 {
		t.Fatalf("file url: %d", w.Code)
	}
}

func TestRedirectToOtherHostIsChecked(t *testing.T) {
	s, _ := newTestServer(t, Config{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host == "api.example.com" {
			http.Redirect(w, r, "http://evil.example.net/steal", 302)
			return
		}
		io.WriteString(w, "should not get here")
	}))
	register(t, s, "p", "api.example.com")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("GET", "http://api.example.com/", "p", nil, ""))
	if w.Code != 403 {
		t.Fatalf("redirect to disallowed host: %d %s", w.Code, w.Body)
	}
	// manual: the 302 comes back to the plugin as is
	w = httptest.NewRecorder()
	r := relayReq("GET", "http://api.example.com/", "p", nil, "")
	r.Header.Set("X-Relay-Redirect", "manual")
	s.ServeHTTP(w, r)
	if w.Code != 200 || w.Header().Get("X-Relay-Status") != "302" {
		t.Fatalf("manual redirect: %d %s", w.Code, w.Header().Get("X-Relay-Status"))
	}
}

// ---------- header mapping ----------

func TestRelayHeaderMappingAndBinaryBody(t *testing.T) {
	var got http.Header
	var gotBody []byte
	var gotMethod string
	bin := []byte{0, 1, 2, 0xff, 0xfe, 'f', 'L', 'a', 'C'}
	s, _ := newTestServer(t, Config{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r.Header.Clone()
		gotMethod = r.Method
		gotBody, _ = io.ReadAll(r.Body)
		w.Header().Add("Set-Cookie", "a=1; Path=/")
		w.Header().Add("Set-Cookie", "b=2; Path=/")
		w.Header().Set("X-Custom", "yes")
		w.WriteHeader(201)
		w.Write(bin)
	}))
	register(t, s, "p", "api.example.com")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("PUT", "https://api.example.com/v1?q=1", "p", [][]string{
		{"Cookie", "session=abc"}, {"User-Agent", "Android15-1070-11440-130-0-LOGIN-wifi"}, {"Referer", "https://h5.kugou.com/"},
		{"Content-Type", "application/json"}, {"dfid", "-"}, {"Connection", "close"}, {"Accept-Encoding", "br"},
	}, `{"x":1}`))
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if gotMethod != "PUT" || string(gotBody) != `{"x":1}` {
		t.Fatalf("method/body: %s %q", gotMethod, gotBody)
	}
	for k, v := range map[string]string{"Cookie": "session=abc", "User-Agent": "Android15-1070-11440-130-0-LOGIN-wifi", "Referer": "https://h5.kugou.com/", "Dfid": "-", "Content-Type": "application/json"} {
		if got.Get(k) != v {
			t.Errorf("upstream %s = %q, want %q", k, got.Get(k), v)
		}
	}
	if got.Get("Accept-Encoding") == "br" {
		t.Error("accept-encoding should be the transport's")
	}
	if w.Header().Get("X-Relay-Status") != "201" {
		t.Errorf("status %s", w.Header().Get("X-Relay-Status"))
	}
	if !bytes.Equal(w.Body.Bytes(), bin) {
		t.Errorf("binary body changed: %v", w.Body.Bytes())
	}
	var cookies []string
	custom := false
	for _, kv := range decodeList(t, w.Header().Get("X-Relay-Headers")) {
		if kv[0] == "set-cookie" {
			cookies = append(cookies, kv[1])
		}
		if kv[0] == "x-custom" && kv[1] == "yes" {
			custom = true
		}
	}
	if len(cookies) != 2 || !custom {
		t.Errorf("response headers: cookies=%v custom=%v", cookies, custom)
	}
	if w.Header().Get("Set-Cookie") != "" {
		t.Error("upstream Set-Cookie must not reach the browser's cookie jar")
	}
}

// ---------- token ----------

func TestToken(t *testing.T) {
	s, _ := newTestServer(t, Config{Token: "s3cret"}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "ok") }))
	register(t, s, "p", "api.example.com")
	for _, p := range []string{"/api/plugins", "/stream?url=http://api.example.com/a.flac", "/img?url=http://api.example.com/a.jpg", "/api/github/zip?repo=a/b"} {
		w := httptest.NewRecorder()
		s.ServeHTTP(w, httptest.NewRequest("GET", p, nil))
		if w.Code != 401 {
			t.Errorf("%s without token: %d", p, w.Code)
		}
	}
	w := httptest.NewRecorder()
	s.ServeHTTP(w, relayReq("GET", "https://api.example.com/", "p", nil, ""))
	if w.Code != 401 {
		t.Fatalf("relay without token: %d", w.Code)
	}
	// Bearer
	r := relayReq("GET", "https://api.example.com/", "p", nil, "")
	r.Header.Set("Authorization", "Bearer s3cret")
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatalf("bearer: %d %s", w.Code, w.Body)
	}
	// wrong token at /api/session
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("POST", "/api/session", strings.NewReader(`{"token":"nope"}`)))
	if w.Code != 401 || len(w.Result().Cookies()) != 0 {
		t.Fatalf("wrong token: %d", w.Code)
	}
	// right token sets an HttpOnly cookie that isn't the token
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("POST", "/api/session", strings.NewReader(`{"token":"s3cret"}`)))
	cs := w.Result().Cookies()
	if w.Code != 200 || len(cs) != 1 || !cs[0].HttpOnly || cs[0].Value == "s3cret" || cs[0].SameSite != http.SameSiteStrictMode {
		t.Fatalf("session: %d %+v", w.Code, cs)
	}
	r = relayReq("GET", "https://api.example.com/", "p", nil, "")
	r.AddCookie(cs[0])
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 200 || w.Body.String() != "ok" {
		t.Fatalf("cookie: %d %s", w.Code, w.Body)
	}
	// status says what's needed without leaking the plugin list
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/api/status", nil))
	var st map[string]any
	json.Unmarshal(w.Body.Bytes(), &st)
	if st["tokenRequired"] != true || st["authenticated"] != false || len(st["plugins"].([]any)) != 0 {
		t.Fatalf("status: %v", st)
	}
}

// ---------- range passthrough ----------

func TestStreamRangePassthrough(t *testing.T) {
	audio := append([]byte("fLaC"), bytes.Repeat([]byte{7}, 100000)...)
	var sawCookie, sawUA string
	s, _ := newTestServer(t, Config{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawCookie, sawUA = r.Header.Get("Cookie"), r.Header.Get("User-Agent")
		if r.URL.Path == "/page.html" {
			w.Header().Set("Content-Type", "text/html")
			io.WriteString(w, "<html>")
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		http.ServeContent(w, r, "", time.Unix(1700000000, 0), bytes.NewReader(audio))
	}))
	register(t, s, "kugou-lite", "gateway.kugou.com")

	r := httptest.NewRequest("GET", "/stream?url="+url.QueryEscape("http://fs.youthandroid2.kugou.com/x/song.flac")+"&h="+url.QueryEscape(b64([][]string{{"User-Agent", "kg"}})), nil)
	r.Header.Set("Range", "bytes=0-3")
	r.AddCookie(&http.Cookie{Name: cookieName, Value: "browser-session"})
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 206 {
		t.Fatalf("status %d %s", w.Code, w.Body)
	}
	if w.Body.String() != "fLaC" {
		t.Fatalf("body %q", w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "audio/flac" {
		t.Errorf("content-type %q", ct)
	}
	if cr := w.Header().Get("Content-Range"); cr != "bytes 0-3/100004" {
		t.Errorf("content-range %q", cr)
	}
	if w.Header().Get("Accept-Ranges") != "bytes" || w.Header().Get("Content-Length") != "4" {
		t.Errorf("headers %v", w.Header())
	}
	if sawCookie != "" || sawUA != "kg" {
		t.Errorf("upstream got cookie %q ua %q", sawCookie, sawUA)
	}
	// a later range
	r = httptest.NewRequest("GET", "/stream?url="+url.QueryEscape("http://fs.youthandroid2.kugou.com/x/song.flac"), nil)
	r.Header.Set("Range", "bytes=100000-")
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 206 || w.Body.Len() != 4 {
		t.Fatalf("tail range: %d len %d", w.Code, w.Body.Len())
	}
	// not media
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/stream?url="+url.QueryEscape("http://www.kugou.com/page.html"), nil))
	if w.Code != 415 {
		t.Fatalf("html through /stream: %d", w.Code)
	}
	// unrelated domain
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/stream?url="+url.QueryEscape("http://evil.example.net/a.flac"), nil))
	if w.Code != 403 {
		t.Fatalf("other domain: %d", w.Code)
	}
}

func TestImg(t *testing.T) {
	s, _ := newTestServer(t, Config{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".svg") {
			w.Header().Set("Content-Type", "image/svg+xml")
		} else {
			w.Header().Set("Content-Type", "image/jpeg")
		}
		w.Write([]byte{0xff, 0xd8, 0xff})
	}))
	register(t, s, "kugou-lite", "gateway.kugou.com")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/img?url="+url.QueryEscape("https://imge.kugou.com/stdmusic/400/a.jpg"), nil))
	if w.Code != 200 || w.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("img: %d %v", w.Code, w.Header())
	}
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/img?url="+url.QueryEscape("https://imge.kugou.com/a.svg"), nil))
	if w.Code != 415 {
		t.Fatalf("svg (script-capable) through /img: %d", w.Code)
	}
}

// ---------- SSRF ----------

func TestPrivateAddressesBlocked(t *testing.T) {
	for _, a := range []string{"127.0.0.1", "10.1.2.3", "192.168.1.1", "172.16.0.1", "169.254.169.254", "100.64.0.1", "::1", "fd00::1", "::ffff:127.0.0.1", "0.0.0.0"} {
		if publicIP(netip.MustParseAddr(a)) {
			t.Errorf("%s counted as public", a)
		}
	}
	if !publicIP(netip.MustParseAddr("140.82.116.4")) {
		t.Error("public address refused")
	}
	// The real transport refuses to dial a private address.
	t.Setenv("HTTPS_PROXY", "")
	t.Setenv("HTTP_PROXY", "")
	t.Setenv("https_proxy", "")
	t.Setenv("http_proxy", "")
	ln := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "internal") }))
	defer ln.Close()
	tr, proxied := newTransport(Config{}, net.DefaultResolver)
	if proxied {
		t.Skip("a proxy is configured in this environment")
	}
	_, err := tr.DialContext(context.Background(), "tcp", strings.TrimPrefix(ln.URL, "http://"))
	if err == nil {
		t.Fatal("dialled a loopback address")
	}
}

// ---------- registry ----------

func makeZip(t *testing.T, files map[string]string) []byte {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	for n, c := range files {
		w, _ := zw.Create(n)
		io.WriteString(w, c)
	}
	zw.Close()
	return b.Bytes()
}

func TestRegisterFromGitHubReadsTheZip(t *testing.T) {
	zipData := makeZip(t, map[string]string{
		"repo-main/plugin.json": `{"id":"demo","version":"1.0.0","permissions":{"network":["api.example.com"]}}`,
		"repo-main/index.js":    "export function home(){}",
	})
	s, _ := newTestServer(t, Config{Token: "t", Repos: []string{"me/repo"}}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/me/repo/zip/refs/heads/main" {
			w.Write(zipData)
			return
		}
		http.NotFound(w, r)
	}))
	s.gh.Codeload = "http://codeload.github.com"
	do := func(body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "/api/plugins", strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer t")
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		return w
	}
	w := do(`{"kind":"github","repo":"me/repo"}`)
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	e, ok := s.reg.Get("demo")
	if !ok || e.Branch != "main" || len(e.Network) != 1 || e.Network[0] != "api.example.com" {
		t.Fatalf("entry %+v", e)
	}
	if w := do(`{"kind":"github","repo":"other/repo"}`); w.Code != 403 {
		t.Fatalf("repo outside RELAY_REPOS: %d", w.Code)
	}
	if w := do(`{"kind":"manifest","manifest":{"id":"z","permissions":{"network":["a.example.com"]}}}`); w.Code != 403 {
		t.Fatalf("upload with RELAY_REPOS: %d", w.Code)
	}
}

func TestManifestUploadPolicy(t *testing.T) {
	s, _ := newTestServer(t, Config{}, http.NotFoundHandler())
	post := func(body string) int {
		w := httptest.NewRecorder()
		s.ServeHTTP(w, httptest.NewRequest("POST", "/api/plugins", strings.NewReader(body)))
		return w.Code
	}
	if c := post(`{"kind":"manifest","manifest":{"id":"z","permissions":{"network":["a.example.com"]}}}`); c != 403 {
		t.Fatalf("no token and no RELAY_ALLOW_MANIFEST_UPLOAD: %d", c)
	}
	s.cfg.AllowUpload = true
	if c := post(`{"kind":"manifest","manifest":{"id":"z","permissions":{"network":["*"]}}}`); c != 400 {
		t.Fatalf("wildcard upload: %d", c)
	}
	if c := post(`{"kind":"manifest","manifest":{"id":"z","permissions":{"network":["a.example.com"]}}}`); c != 200 {
		t.Fatalf("upload allowed: %d", c)
	}
}

func TestRegistryPersists(t *testing.T) {
	p := filepath.Join(t.TempDir(), "d", "plugins.json")
	r, _ := NewRegistry(p)
	r.Put(Entry{ID: "a", Network: []string{"x.example.com"}})
	r2, err := NewRegistry(p)
	if err != nil {
		t.Fatal(err)
	}
	if e, ok := r2.Get("a"); !ok || e.Network[0] != "x.example.com" {
		t.Fatal("not persisted")
	}
}

// ---------- static ----------

func TestStatic(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "index.html"), []byte("<!doctype html>"+strings.Repeat(" ", 2000)), 0o644)
	os.WriteFile(filepath.Join(dir, "main.dart.js"), []byte(strings.Repeat("var a=1;", 1000)), 0o644)
	s := NewServer(Config{StaticDir: dir}, &Registry{entries: map[string]Entry{}}, http.DefaultTransport, false)

	r := httptest.NewRequest("GET", "/some/deep/link?install=a/b", nil)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 200 || !strings.HasPrefix(w.Body.String(), "<!doctype html>") {
		t.Fatalf("spa fallback: %d", w.Code)
	}
	if w.Header().Get("Cross-Origin-Embedder-Policy") != "require-corp" || w.Header().Get("Cache-Control") != "no-cache" {
		t.Errorf("headers %v", w.Header())
	}
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/missing.js", nil))
	if w.Code != 404 {
		t.Fatalf("missing asset: %d", w.Code)
	}
	r = httptest.NewRequest("GET", "/main.dart.js", nil)
	r.Header.Set("Accept-Encoding", "gzip, br")
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Header().Get("Content-Encoding") != "gzip" || w.Body.Len() >= 8000 {
		t.Fatalf("gzip: %v len %d", w.Header(), w.Body.Len())
	}
	etag := w.Header().Get("ETag")
	r = httptest.NewRequest("GET", "/main.dart.js", nil)
	r.Header.Set("Accept-Encoding", "gzip")
	r.Header.Set("If-None-Match", etag)
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 304 {
		t.Fatalf("revalidate: %d", w.Code)
	}
}
