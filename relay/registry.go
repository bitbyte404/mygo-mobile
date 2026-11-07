package main

// The registry: which plugins the relay serves and the hosts each may reach
// (its plugin.json permissions.network). It is the relay's allowlist.
//
// A plugin gets in one of two ways:
//   - from GitHub: the client names owner/repo (and branch); the relay
//     downloads the repository zip itself and reads plugin.json from it, so a
//     client cannot claim hosts the plugin does not declare.
//   - from an uploaded manifest (plugins installed from a zip file): only when
//     the operator allows it (RELAY_ALLOW_MANIFEST_UPLOAD=1, or a RELAY_TOKEN
//     is set so only authenticated clients can register), and never when
//     RELAY_REPOS restricts registration to listed repositories.

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

type Entry struct {
	ID         string   `json:"id"`
	Name       string   `json:"name"`
	Version    string   `json:"version"`
	Network    []string `json:"network"`
	Source     string   `json:"source"` // github | manifest
	Repo       string   `json:"repo,omitempty"`
	Branch     string   `json:"branch,omitempty"`
	Registered int64    `json:"registered"`
}

type Registry struct {
	mu      sync.RWMutex
	path    string // "" = memory only
	entries map[string]Entry
}

func NewRegistry(path string) (*Registry, error) {
	r := &Registry{path: path, entries: map[string]Entry{}}
	if path == "" {
		return r, nil
	}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return r, nil
	}
	if err != nil {
		return nil, err
	}
	var list []Entry
	if err := json.Unmarshal(b, &list); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	for _, e := range list {
		r.entries[e.ID] = e
	}
	return r, nil
}

func (r *Registry) saveLocked() error {
	if r.path == "" {
		return nil
	}
	list := make([]Entry, 0, len(r.entries))
	for _, e := range r.entries {
		list = append(list, e)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].ID < list[j].ID })
	b, _ := json.MarshalIndent(list, "", "  ")
	if err := os.MkdirAll(filepath.Dir(r.path), 0o755); err != nil {
		return err
	}
	tmp := r.path + ".part"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, r.path)
}

func (r *Registry) Put(e Entry) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.entries[e.ID] = e
	return r.saveLocked()
}

func (r *Registry) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.entries, id)
	return r.saveLocked()
}

func (r *Registry) Get(id string) (Entry, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	e, ok := r.entries[id]
	return e, ok
}

func (r *Registry) List() []Entry {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]Entry, 0, len(r.entries))
	for _, e := range r.entries {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// AllPatterns is the union of every registered plugin's hosts.
func (r *Registry) AllPatterns() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	var out []string
	for _, e := range r.entries {
		out = append(out, e.Network...)
	}
	return out
}

// manifest is the part of plugin.json the relay reads.
type manifest struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Version     string `json:"version"`
	Permissions struct {
		Network []string `json:"network"`
	} `json:"permissions"`
}

var idRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`)
var repoRe = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$`)
var branchRe = regexp.MustCompile(`^[A-Za-z0-9_./-]{1,100}$`)

// entryFromManifest validates a plugin.json for the relay.
func entryFromManifest(b []byte) (Entry, error) {
	var m manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return Entry{}, fmt.Errorf("plugin.json: %w", err)
	}
	m.ID = strings.TrimSpace(m.ID)
	if !idRe.MatchString(m.ID) {
		return Entry{}, fmt.Errorf("plugin.json: bad id %q", m.ID)
	}
	e := Entry{ID: m.ID, Name: m.Name, Version: m.Version}
	seen := map[string]bool{}
	for _, h := range m.Permissions.Network {
		h = strings.ToLower(strings.TrimSpace(h))
		if err := validPattern(h); err != nil {
			return Entry{}, fmt.Errorf("plugin %s: network %q: %w", m.ID, h, err)
		}
		if !seen[h] {
			seen[h] = true
			e.Network = append(e.Network, h)
		}
	}
	return e, nil
}

// manifestFromZip finds plugin.json at the zip's root or one folder deep (the
// folder GitHub wraps a repository in), as the app's installer does.
func manifestFromZip(data []byte) ([]byte, error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, errors.New("not a zip file")
	}
	var best *zip.File
	bestDepth := 99
	for _, f := range zr.File {
		name := strings.ReplaceAll(f.Name, `\`, "/")
		if strings.HasPrefix(name, "__MACOSX/") || !strings.HasSuffix("/"+name, "/plugin.json") {
			continue
		}
		depth := strings.Count(name, "/")
		if depth <= 1 && depth < bestDepth {
			best, bestDepth = f, depth
		}
	}
	if best == nil {
		return nil, errors.New("no plugin.json at the top of the zip")
	}
	rc, err := best.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	return io.ReadAll(io.LimitReader(rc, 1<<20))
}

// GitHub downloads repository zips (codeload, which sends no usable CORS
// headers for the browser) and keeps each for a few minutes, so the zip the
// listener reviewed is the one the relay registers.
type GitHub struct {
	Client   *http.Client
	Codeload string // https://codeload.github.com
	Raw      string // https://raw.githubusercontent.com
	TTL      time.Duration

	mu    sync.Mutex
	cache map[string]cachedZip
}

type cachedZip struct {
	data []byte
	at   time.Time
}

const maxZip = 64 << 20

func (g *GitHub) get(url string, limit int64) ([]byte, int, error) {
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", "mygo-relay")
	res, err := g.Client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		io.Copy(io.Discard, io.LimitReader(res.Body, 1<<16))
		return nil, res.StatusCode, fmt.Errorf("HTTP %d: %s", res.StatusCode, url)
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, limit+1))
	if err != nil {
		return nil, 0, err
	}
	if int64(len(b)) > limit {
		return nil, 0, fmt.Errorf("too big: %s", url)
	}
	return b, 200, nil
}

// Zip answers the repository's zip at branch ("" = main, else master), and
// the branch it came from.
func (g *GitHub) Zip(repo, branch string) ([]byte, string, int, error) {
	if !repoRe.MatchString(repo) || strings.Contains(repo, "..") {
		return nil, "", 400, fmt.Errorf("not a GitHub repository: %q", repo)
	}
	branches := []string{"main", "master"}
	if branch != "" {
		if !branchRe.MatchString(branch) || strings.Contains(branch, "..") {
			return nil, "", 400, fmt.Errorf("bad branch %q", branch)
		}
		branches = []string{branch}
	}
	var lastErr error
	lastStatus := 502
	for _, b := range branches {
		key := repo + "@" + b
		g.mu.Lock()
		if g.cache == nil {
			g.cache = map[string]cachedZip{}
		}
		for k, c := range g.cache {
			if time.Since(c.at) > g.TTL {
				delete(g.cache, k)
			}
		}
		c, ok := g.cache[key]
		g.mu.Unlock()
		if ok {
			return c.data, b, 200, nil
		}
		data, status, err := g.get(fmt.Sprintf("%s/%s/zip/refs/heads/%s", g.Codeload, repo, b), maxZip)
		if err == nil {
			g.mu.Lock()
			g.cache[key] = cachedZip{data, time.Now()}
			g.mu.Unlock()
			return data, b, 200, nil
		}
		lastErr = err
		if status == 404 {
			lastStatus = 404
			continue
		}
		return nil, "", 502, err
	}
	return nil, "", lastStatus, lastErr
}

// Manifest answers the repository's plugin.json (raw.githubusercontent.com at
// the root; else the zip), for update checks.
func (g *GitHub) Manifest(repo, branch string) ([]byte, error) {
	if !repoRe.MatchString(repo) || strings.Contains(repo, "..") {
		return nil, fmt.Errorf("not a GitHub repository: %q", repo)
	}
	if branch == "" {
		branch = "main"
	}
	if !branchRe.MatchString(branch) || strings.Contains(branch, "..") {
		return nil, fmt.Errorf("bad branch %q", branch)
	}
	if b, _, err := g.get(fmt.Sprintf("%s/%s/%s/plugin.json", g.Raw, repo, branch), 1<<20); err == nil {
		return b, nil
	}
	data, _, _, err := g.Zip(repo, branch)
	if err != nil {
		return nil, err
	}
	return manifestFromZip(data)
}
