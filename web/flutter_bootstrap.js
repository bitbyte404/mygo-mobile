{{flutter_js}}
{{flutter_build_config}}

// Everything comes from this origin: CanvasKit is bundled
// (--no-web-resources-cdn), the CJK font is in fonts/, and Flutter's rare-glyph
// fallback fonts (emoji, other scripts) go through the relay's /gfonts/ cache
// instead of fonts.gstatic.com (the page runs cross-origin isolated).
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: new URL('gfonts/', document.baseURI).href,
  },
});
