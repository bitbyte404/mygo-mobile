// Typed errors that cross the layers. A plugin's failure keeps the desktop
// app's error codes (internal/music: ErrSignIn, ErrSetup, ...), so the UI can
// offer the remedy (sign in, open settings) whatever the runtime.
/// An error a plugin threw: [code] is signIn, setup, unavailable, unsupported
/// or empty, as the desktop's music.Err* are.
class PluginError implements Exception {
  PluginError(this.code, this.message);
  final String code;
  final String message;

  static const signIn = 'signIn', setup = 'setup', unavailable = 'unavailable', unsupported = 'unsupported';

  @override
  String toString() {
    switch (code) {
      case signIn:
        return message.isEmpty ? 'sign in first' : message;
      case setup:
        return message.isEmpty ? 'the plugin needs setting up' : message;
      case unavailable:
        return message.isEmpty ? 'not available' : message;
      case unsupported:
        return message.isEmpty ? 'not supported by this source' : message;
    }
    return message.isEmpty ? 'the plugin failed' : message;
  }

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

