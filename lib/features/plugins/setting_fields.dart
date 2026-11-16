// The fields of a plugin's settings page, one widget per SettingType
// (core/plugin/manifest.dart). Each draws its SettingField and hands every
// change to the PluginSettingsController; none saves anything itself.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/data/plugins/plugin_settings.dart';
import 'package:mygo_mobile/l10n/strings.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// One setting: its label, the control for its type, its help and link,
/// and Retry / Restore after a failed save.
class SettingFieldView extends StatelessWidget {
  const SettingFieldView({super.key, required this.field, required this.controller, required this.translate, required this.strings});
  final SettingField field;
  final PluginSettingsController controller;

  /// The plugin's own translations (labels, help, option labels).
  final String Function(String) translate;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final pal = context.mg;
    final def = field.def;
    final label = translate(def.label);
    final control = switch (field.type) {
      SettingType.text => _TextSetting(field: field, controller: controller),
      SettingType.password => _TextSetting(field: field, controller: controller, password: true, strings: strings),
      SettingType.boolean => _BooleanSetting(field: field, controller: controller, label: label),
      SettingType.select => _SelectSetting(field: field, controller: controller, label: label, translate: translate, strings: strings),
    };
    final title = Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (field.type == SettingType.boolean)
        Row(children: [Expanded(child: title), control])
      else ...[
        title,
        const SizedBox(height: 6),
        control,
      ],
      if (field.failed)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text(strings['settingsSaveFailed'], style: TextStyle(fontSize: 12.5, color: pal.accent))),
            TextAction(strings['retry'], accent: true, onTap: field.saving ? null : () => controller.retry(def.key)),
            TextAction(strings['restore'], onTap: field.saving ? null : () => controller.restore(def.key)),
          ]),
        ),
      if (def.help.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(translate(def.help), style: TextStyle(fontSize: 12.5, color: pal.muted, height: 1.4))),
      if (def.link.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextAction(def.link, accent: true, onTap: () => launchUrl(Uri.parse(def.link), mode: LaunchMode.externalApplication)),
        ),
    ]);
  }
}

/// Text and passwords: a draft until Save. A password is masked, with a
/// button to show it while typing.
class _TextSetting extends StatefulWidget {
  const _TextSetting({required this.field, required this.controller, this.password = false, this.strings});
  final SettingField field;
  final PluginSettingsController controller;
  final bool password;
  final S? strings;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _text = TextEditingController(text: widget.field.draft);
  bool _shown = false;

  @override
  void didUpdateWidget(_TextSetting old) {
    super.didUpdateWidget(old);
    // Restore puts the saved value back.
    if (_text.text != widget.field.draft) _text.text = widget.field.draft;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = MgTextField(
      controller: _text,
      obscure: widget.password && !_shown,
      mono: widget.password && _shown,
      onChanged: (v) => widget.controller.edit(widget.field.def.key, v),
    );
    if (!widget.password) return field;
    final s = widget.strings!;
    return Row(children: [
      Expanded(child: field),
      const SizedBox(width: 4),
      TextAction(_shown ? s['hide'] : s['show'], onTap: () => setState(() => _shown = !_shown)),
    ]);
  }
}

/// A switch: saves "true" / "false" as it changes. Unset shows as off and
/// writes nothing until touched.
class _BooleanSetting extends StatelessWidget {
  const _BooleanSetting({required this.field, required this.controller, required this.label});
  final SettingField field;
  final PluginSettingsController controller;
  final String label;

  @override
  Widget build(BuildContext context) => MgSwitch(
        value: field.draft == 'true',
        enabled: !field.saving,
        semanticLabel: label,
        onChanged: (on) => controller.choose(field.def.key, on ? 'true' : 'false'),
      );
}

/// A select: the chosen option's label; a sheet of the options to choose
/// from; saves the option's value as it changes. A saved value that isn't
/// one of the options shows as "Current value [x]" and stays until another
/// is chosen.
class _SelectSetting extends StatelessWidget {
  const _SelectSetting({required this.field, required this.controller, required this.label, required this.translate, required this.strings});
  final SettingField field;
  final PluginSettingsController controller;
  final String label;
  final String Function(String) translate;
  final S strings;

  String get _shown {
    for (final o in field.def.options) {
      if (o.value == field.draft) return translate(o.label);
    }
    return '${strings['settingCurrentValue']} [${field.draft}]';
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showMgSheet<SettingOption>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Text(label, style: MgType.section.copyWith(fontSize: 17, color: ctx.mg.text))),
          for (final o in field.def.options)
            MgListRow(
              label: translate(o.label),
              selected: o.value == field.draft,
              trailing: o.value == field.draft ? MgIcon(MgIcons.check, size: 16, color: ctx.mg.accent) : null,
              onTap: () => Navigator.pop(ctx, o),
            ),
        ]),
      ),
    );
    if (chosen != null) controller.choose(field.def.key, chosen.value);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.mg;
    return Opacity(
      opacity: field.saving ? 0.5 : 1,
      child: Pressable(
        onTap: field.saving ? null : () => _pick(context),
        color: pal.dark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color.fromRGBO(0, 0, 0, 0.05),
        pressedColor: pal.press,
        borderRadius: BorderRadius.circular(10),
        semanticLabel: label,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 40,
          child: Row(children: [
            Expanded(child: Text(_shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: pal.text))),
            if (field.saving) const SizedBox(width: 16, height: 16, child: MgSpinner()) else MgIcon(MgIcons.upDown, size: 15, color: pal.muted),
          ]),
        ),
      ),
    );
  }
}
