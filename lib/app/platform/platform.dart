// Picks the phone or browser variant at compile time.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'platform_bits.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart' as impl;

export 'platform_bits.dart';

Future<PlatformBits> platformBits() => impl.platformBits();

/// Web: registers the bundled CJK font (web/fonts) so Chinese text never
/// depends on Google's font CDN. No-op on phones.
Future<void> loadAppFonts() => impl.loadAppFonts();

/// Insets of the screen the engine doesn't report: on the web, the notch,
/// the home indicator and Safari's toolbar (env(safe-area-inset-*)). Zero
/// on phones, where Flutter has them already.
ValueListenable<EdgeInsets> get systemInsets => impl.systemInsets;

/// Reports a failure where it can be read later (the relay's log on the
/// web); nothing on phones.
void reportClientError(String kind, String message) => impl.reportClientError(kind, message);

/// The media element's own clock, where there is one (the web).
Duration? mediaClock() => impl.mediaClock();

/// Publishes a value for browser tests (window.__mygo); nothing on phones.
void debugExpose(String key, Object? value) => impl.debugExpose(key, value);

/// A query parameter of the page (web), else null.
String? pageParam(String name) => impl.pageParam(name);

/// Lets browser tests read the lyrics clock (window.__mygoPosition).
void exposeClock(Duration Function() now) => impl.exposeClock(now);
