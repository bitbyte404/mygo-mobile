// Signing in with a plugin: its QR code / link prompt in a dialog.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/ui/ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Signs in with the plugin, showing what it asks shown on the way: a QR
/// code to scan (host.signInPrompt), and its text. Answers whether it worked.
Future<bool> signIn(BuildContext context, InstalledPlugin p) async {
  svc.plugins.signInPrompt.value = null;
  final call = svc.music.signIn(p.id);
  final s = svc.s;
  final ok = await showMgDialog<bool>(
    context,
    dismissible: false,
    title: '${s['signIn']} · ${p.name}',
    content: _SignInBody(call: call),
    actions: (ctx) => [PillButton(label: s['cancel'], onTap: () => Navigator.pop(ctx, false))],
  );
  return ok == true;
}

class _SignInBody extends StatefulWidget {
  const _SignInBody({required this.call});
  final Future<void> call;

  @override
  State<_SignInBody> createState() => _SignInBodyState();
}

class _SignInBodyState extends State<_SignInBody> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.call.then((_) {
      if (mounted) Navigator.pop(context, true);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = context.mg;
    return ValueListenableBuilder<SignInPrompt?>(
      valueListenable: svc.plugins.signInPrompt,
      builder: (context, prompt, _) {
        if (_error != null) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            MgIcon(MgIcons.alert, size: 36, color: p.accent),
            const SizedBox(height: 12),
            Text('${s['signInFailed']}: ${svc.describe(_error!)}', textAlign: TextAlign.center),
          ]);
        }
        if (prompt == null) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            const MgSpinner(),
            const SizedBox(height: 14),
            Text(s['waiting'], style: TextStyle(color: p.muted)),
          ]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (prompt.qr.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: QrImageView(data: prompt.qr, size: 220, backgroundColor: Colors.white),
              ),
            ),
          const SizedBox(height: 12),
          if (prompt.text.isNotEmpty) Text(prompt.text, textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
        ]);
      },
    );
  }
}

