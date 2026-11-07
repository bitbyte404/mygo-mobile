// Picks the phone or browser variant at compile time.
import 'platform_bits.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart' as impl;

export 'platform_bits.dart';

Future<PlatformBits> platformBits() => impl.platformBits();

/// Web: registers the bundled CJK font (web/fonts) so Chinese text never
/// depends on Google's font CDN. No-op on phones.
Future<void> loadAppFonts() => impl.loadAppFonts();
