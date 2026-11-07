# MyGo 音乐 web: the Flutter web build served by the Go relay.
#   docker build -t mygo-web .
#   docker run -p 8080:8080 -e RELAY_TOKEN=... -v $PWD/data:/data mygo-web
# See docs/WEB.md. For a server that only runs prebuilt files: Dockerfile.prebuilt.

ARG FLUTTER_VERSION=3.47.9
ARG GO_VERSION=1.27

# ---- 1. Flutter web build (always on the build machine's arch) ----
FROM --platform=$BUILDPLATFORM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS web
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --no-analytics >/dev/null && flutter pub get
COPY . .
RUN flutter build web --release --no-web-resources-cdn \
 && find build/web -type f \( -name '*.js' -o -name '*.json' -o -name '*.html' -o -name '*.wasm' -o -name '*.otf' -o -name '*.ttf' -o -name '*.frag' -o -name '*.bin' \) \
      -size +1k -exec gzip -9 -k {} \;

# ---- 2. Relay: static Go binary, cross-compiled for the target ----
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS relay
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY relay/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/mygo-relay . \
 && mkdir -p /out/data

# ---- 3. Runtime: distroless, non-root ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=relay /out/mygo-relay /app/mygo-relay
COPY --from=web /src/build/web /app/web
COPY --from=relay --chown=65532:65532 /out/data /data
ENV LISTEN=:8080 RELAY_STATIC=/app/web RELAY_DATA=/data
EXPOSE 8080
VOLUME ["/data"]
USER nonroot
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s CMD ["/app/mygo-relay", "-healthcheck"]
ENTRYPOINT ["/app/mygo-relay"]
