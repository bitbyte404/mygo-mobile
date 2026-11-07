// The web build's first screen when its relay wants an access token
// (RELAY_TOKEN): asked once, exchanged for the relay's HttpOnly session
// cookie, which the browser then sends with every plugin fetch, stream and
// cover. Also shown again (as a dialog) if the relay later says no.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/system_insets.dart';
import 'package:mygo_mobile/data/relay/relay_client.dart';
import 'package:mygo_mobile/l10n/strings.dart';
import 'package:mygo_mobile/ui/ui.dart';

String _deviceLang() => PlatformDispatcher.instance.locale.languageCode == 'zh' ? 'zh-CN' : 'en';

/// Returns once the relay accepts this browser: at once when it needs no
/// token or already has a session, else after the token screen.
Future<void> ensureRelaySession(RelayClient relay) async {
  try {
    final st = await relay.status();
    if (!st.tokenRequired || st.authenticated) return;
  } catch (_) {
    // Unreachable: the screen says so and retries.
  }
  final done = Completer<void>();
  runApp(_GateApp(relay: relay, s: S(_deviceLang()), onDone: done.complete));
  await done.future;
}

/// The token form as a dialog, when a plugin's request came back 401.
Future<void> showRelayTokenDialog(BuildContext context, RelayClient relay, S s) => showMgDialog<void>(
      context,
      dismissible: false,
      content: SizedBox(width: 380, child: RelayTokenForm(relay: relay, s: s, onDone: () => Navigator.of(context, rootNavigator: true).pop())),
      actions: (_) => const [],
    );

class _GateApp extends StatelessWidget {
  const _GateApp({required this.relay, required this.s, required this.onDone});
  final RelayClient relay;
  final S s;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: s['appName'],
      theme: mgTheme(MgPalette.lightPalette),
      darkTheme: mgTheme(MgPalette.darkPalette),
      builder: (context, child) => SystemInsets(child: child!),
      home: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: context.mg.bg,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: RelayTokenForm(relay: relay, s: s, onDone: onDone)),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class RelayTokenForm extends StatefulWidget {
  const RelayTokenForm({super.key, required this.relay, required this.s, required this.onDone});
  final RelayClient relay;
  final S s;
  final VoidCallback onDone;

  @override
  State<RelayTokenForm> createState() => _RelayTokenFormState();
}

class _RelayTokenFormState extends State<RelayTokenForm> {
  final _token = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final st = await widget.relay.status();
      if (!st.tokenRequired || st.authenticated) {
        widget.onDone();
        return;
      }
      if (await widget.relay.signIn(_token.text)) {
        widget.onDone();
        return;
      }
      _error = widget.s['relayTokenWrong'];
    } catch (_) {
      _error = widget.s['relayUnreachable'];
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final s = widget.s;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        MgIcon(MgIcons.lock, size: 22, color: p.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(s['relayTitle'], style: MgType.section.copyWith(color: p.text))),
      ]),
      const SizedBox(height: 12),
      Text(s['relayTokenHelp'], style: TextStyle(color: p.muted, fontSize: 14, height: 1.5)),
      const SizedBox(height: 18),
      MgTextField(controller: _token, hint: s['relayTokenHint'], icon: MgIcons.lock, obscure: true, autofocus: true, onSubmitted: (_) => _submit()),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: p.accent, fontSize: 13))),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerRight,
        child: _busy ? const Padding(padding: EdgeInsets.all(8), child: MgSpinner()) : PillButton(primary: true, label: s['continue'], onTap: _submit),
      ),
    ]);
  }
}
