{{flutter_js}}
{{flutter_build_config}}

// Everything comes from this origin: CanvasKit is bundled
// (--no-web-resources-cdn), the CJK font is in fonts/, and Flutter's rare-glyph
// fallback fonts (emoji, other scripts) go through the relay's /gfonts/ cache
// instead of fonts.gstatic.com (the page runs cross-origin isolated).
//
// The app renders into #app (custom-element embedding) rather than taking
// over <body>: index.html sizes #app to the visible viewport and keeps its
// own viewport meta (viewport-fit=cover, no zoom), which full-page mode
// would replace.
if (window.mygoMeasure) window.mygoMeasure();
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: new URL('gfonts/', document.baseURI).href,
    hostElement: document.getElementById('app'),
  },
});
