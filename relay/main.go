// Command mygo-relay serves MyGo 音乐's web build and relays its plugins'
// network traffic (fetch, audio streams, cover art) under an allowlist made
// of the installed plugins' declared hosts. See docs/WEB.md.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func env(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func list(k string) []string {
	var out []string
	for _, s := range strings.Split(os.Getenv(k), ",") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func truthy(k string) bool {
	switch strings.ToLower(os.Getenv(k)) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

func main() {
	health := flag.Bool("healthcheck", false, "probe the running relay's /healthz and exit 0 when it answers (for container health checks)")
	flag.Parse()
	addr := env("LISTEN", ":8080")
	if *health {
		_, port, err := net.SplitHostPort(addr)
		if err != nil {
			port = "8080"
		}
		c := &http.Client{Timeout: 3 * time.Second}
		res, err := c.Get("http://127.0.0.1:" + port + "/healthz")
		if err != nil || res.StatusCode != 200 {
			fmt.Fprintln(os.Stderr, "unhealthy:", err)
			os.Exit(1)
		}
		os.Exit(0)
	}

	cfg := Config{
		Token:        os.Getenv("RELAY_TOKEN"),
		Repos:        list("RELAY_REPOS"),
		MediaHosts:   list("RELAY_MEDIA_HOSTS"),
		AllowUpload:  truthy("RELAY_ALLOW_MANIFEST_UPLOAD"),
		AllowPrivate: truthy("RELAY_ALLOW_PRIVATE"),
		SecureCookie: truthy("RELAY_SECURE_COOKIE"),
		StaticDir:    env("RELAY_STATIC", "web"),
	}
	for _, h := range cfg.MediaHosts {
		if err := validPattern(h); err != nil {
			log.Fatalf("RELAY_MEDIA_HOSTS: %v", err)
		}
	}
	dataDir := env("RELAY_DATA", "data")
	reg, err := NewRegistry(filepath.Join(dataDir, "plugins.json"))
	if err != nil {
		log.Fatal(err)
	}
	rt, proxied := newTransport(cfg, net.DefaultResolver)
	s := NewServer(cfg, reg, rt, proxied)
	if cfg.Token == "" {
		log.Printf("WARNING: RELAY_TOKEN is not set; anyone who can reach %s can use the relay (for the registered plugins' hosts only)", addr)
	}
	if cfg.AllowPrivate {
		log.Printf("WARNING: RELAY_ALLOW_PRIVATE is set; requests may reach private addresses")
	}
	srv := &http.Server{Addr: addr, Handler: s, ReadHeaderTimeout: 20 * time.Second, IdleTimeout: 120 * time.Second}
	go func() {
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, os.Interrupt, syscall.SIGTERM)
		<-ch
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	}()
	log.Printf("mygo-relay %s listening on %s (static %s, data %s, plugins %d, proxy %v)", version, addr, cfg.StaticDir, dataDir, len(reg.List()), proxied)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
