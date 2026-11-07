// Sheets, dialogs, toasts and the text field.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';
import 'buttons.dart';

/// A sheet from the foot of the screen, on the root navigator (over the
/// mini player and Now Playing): popover colors, 20-point top corners, a
/// grabber, the gesture bar's room kept below.
Future<T?> showMgSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false, double initialSize = 0.7}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      final p = ctx.mg;
      final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
      Widget body(Widget child) => Container(
            decoration: BoxDecoration(
              color: p.popover,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(MgRadius.sheet)),
              border: Border(top: BorderSide(color: p.popoverEdge, width: 0.5)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Container(width: 36, height: 5, decoration: BoxDecoration(color: p.faint, borderRadius: BorderRadius.circular(3))),
              ),
              Flexible(child: child),
            ]),
          );
      if (scrollable) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: initialSize,
          maxChildSize: 0.95,
          builder: (ctx, controller) => body(PrimaryScrollController(controller: controller, child: Padding(padding: EdgeInsets.only(bottom: bottom), child: builder(ctx)))),
        );
      }
      return body(Padding(padding: EdgeInsets.only(bottom: bottom + 8), child: builder(ctx)));
    },
  );
}

/// A confirm dialog in popover colors: [ok] is the accent pill.
Future<bool> showMgConfirm(BuildContext context, {required String title, String message = '', required String ok, required String cancel}) async {
  final r = await showMgDialog<bool>(
    context,
    title: title,
    content: message.isEmpty ? null : Text(message),
    actions: (ctx) => [
      PillButton(label: cancel, onTap: () => Navigator.pop(ctx, false)),
      PillButton(label: ok, primary: true, onTap: () => Navigator.pop(ctx, true)),
    ],
  );
  return r == true;
}

Future<T?> showMgDialog<T>(BuildContext context, {String? title, Widget? content, required List<Widget> Function(BuildContext) actions, bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'dialog',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: MgMotion.ease);
      return Opacity(opacity: t.value, child: Transform.scale(scale: 0.94 + 0.06 * t.value, child: child));
    },
    pageBuilder: (ctx, _, _) {
      final p = ctx.mg;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                  decoration: BoxDecoration(
                    color: p.popover,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.popoverEdge, width: 0.5),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.2), blurRadius: 24, spreadRadius: -4, offset: Offset(0, 8))],
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(fontSize: 14, height: 1.45, color: p.text),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (title != null) ...[Text(title, style: MgType.section.copyWith(fontSize: 17, color: p.text)), const SizedBox(height: 12)],
                      if (content != null) Flexible(child: content),
                      const SizedBox(height: 18),
                      Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: actions(ctx)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

OverlayEntry? _toastEntry;
Timer? _toastTimer;

/// A short message in a pill above the foot of the screen (MyGo's c.Toast),
/// clear of the mini player and the tab bar, gone after 3 s.
void toast(BuildContext context, String msg) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  _toastTimer?.cancel();
  final entry = OverlayEntry(builder: (ctx) => _Toast(msg: msg));
  _toastEntry = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(seconds: 3), () {
    if (_toastEntry == entry) {
      entry.remove();
      _toastEntry = null;
    }
  });
}

class _Toast extends StatelessWidget {
  const _Toast({required this.msg});
  final String msg;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 140;
    return Positioned(
      left: 24,
      right: 24,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: MgMotion.ease,
            builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: p.popover,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.popoverEdge, width: 0.5),
                boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.2), blurRadius: 24, spreadRadius: -4, offset: Offset(0, 8))],
              ),
              child: Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: p.text, decoration: TextDecoration.none, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line text field in the search field's style: a soft rounded fill,
/// a magnifier, a clear button.
class MgTextField extends StatelessWidget {
  const MgTextField({super.key, required this.controller, this.hint = '', this.icon, this.onChanged, this.onSubmitted, this.autofocus = false, this.action, this.focusNode, this.onClear, this.mono = false, this.obscure = false});
  final TextEditingController controller;
  final String hint;
  final MgIconData? icon;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool autofocus, mono, obscure;
  final TextInputAction? action;
  final FocusNode? focusNode;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: p.dark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color.fromRGBO(0, 0, 0, 0.05), borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        if (icon != null) ...[MgIcon(icon!, size: 17, color: p.muted), const SizedBox(width: 8)],
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            obscureText: obscure,
            autocorrect: !obscure,
            textInputAction: action,
            cursorColor: p.accent,
            style: TextStyle(fontSize: 15, color: p.text, fontFamily: mono ? 'monospace' : null),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 15, color: p.faint),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged?.call('');
                    onClear?.call();
                  },
                  child: Padding(padding: const EdgeInsets.all(4), child: MgIcon(MgIcons.x, size: 15, color: p.muted)),
                ),
        ),
      ]),
    );
  }
}
