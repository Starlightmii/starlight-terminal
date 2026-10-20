import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;

import '../../core/palette.dart';
import '../../core/providers.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// Provider configuration: paste keys, pick models, add custom endpoints.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  ProviderKind _filter = ProviderKind.llm;
  final Set<String> _expanded = <String>{};
  bool _showKey = false;

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final list = studio.ofKind(_filter);

    return Column(
      children: [
        _summary(studio, palette),
        const SizedBox(height: 8),
        _filterBar(palette),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: '${_filter.name.toUpperCase()} PROVIDERS',
            accent: true,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            trailing: InkWell(
              onTap: () => _addCustomDialog(context, studio, palette),
              child: Text(
                '+ CUSTOM',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _providerCard(
                context,
                studio,
                palette,
                list[i],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summary(StudioController studio, Palette palette) {
    final total = studio.providers.length;
    final ready = studio.configuredCount;
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KEY VAULT',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: palette.bright,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$ready of $total providers configured',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9,
                    color: palette.dim,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$ready',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: ready > 0 ? palette.ok : palette.warn,
                  shadows: ready > 0
                      ? [
                          Shadow(
                            color: palette.ok.withValues(alpha: 0.7),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
              Text(
                'READY',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 7.5,
                  letterSpacing: 1.2,
                  color: palette.dim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterBar(Palette palette) {
    return Row(
      children: [
        for (final k in ProviderKind.values) ...[
          _chip(
            palette,
            k.name.toUpperCase(),
            _filter == k,
            () => setState(() => _filter = k),
          ),
          const SizedBox(width: 6),
        ],
        const Spacer(),
        InkWell(
          onTap: () => setState(() => _showKey = !_showKey),
          child: Text(
            _showKey ? 'HIDE KEYS' : 'SHOW KEYS',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              letterSpacing: 0.9,
              color: _showKey ? palette.warn : palette.dim,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    Palette palette,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? palette.mid.withValues(alpha: 0.16) : null,
          border: Border.all(color: active ? palette.mid : palette.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8.5,
            letterSpacing: 1,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Widget _providerCard(
    BuildContext context,
    StudioController studio,
    Palette palette,
    Provider p,
  ) {
    final open = _expanded.contains(p.id);
    final cors = ProviderPresets.typicallyAllowsBrowserCors(p);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: p.ready && p.looksPlausible ? palette.mid : palette.line,
        ),
        color: palette.bg.withValues(alpha: 0.32),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(p.id);
              } else {
                _expanded.add(p.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              child: Row(
                children: [
                  Text(
                    p.enabled ? '●' : '○',
                    style: TextStyle(
                      fontSize: 9,
                      color: p.ready && p.looksPlausible
                          ? palette.ok
                          : palette.dim,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: p.enabled ? palette.bright : palette.dim,
                          ),
                        ),
                        Text(
                          p.model.isEmpty ? 'no model set' : p.model,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8.5,
                            color: palette.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showKey && p.apiKey.isNotEmpty ? p.maskedKey : p.maskedKey,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 8.5,
                      color: p.apiKey.isEmpty ? palette.dim : palette.mid,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    open ? '▾' : '▸',
                    style: TextStyle(fontSize: 10, color: palette.dim),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  _field(
                    palette,
                    label: 'API KEY',
                    initial: _showKey ? p.apiKey : '',
                    hint: _showKey ? 'paste key' : 'secret hidden',
                    onChanged: (v) => studio.setKey(p.id, v),
                  ),
                  const SizedBox(height: 5),
                  _field(
                    palette,
                    label: 'MODEL',
                    initial: p.model,
                    hint: 'model id',
                    onChanged: (v) => studio.setModel(p.id, v),
                  ),
                  const SizedBox(height: 5),
                  _field(
                    palette,
                    label: 'BASE URL',
                    initial: p.baseUrl,
                    hint: 'https://…/v1',
                    onChanged: (v) => studio.setBaseUrl(p.id, v),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      _mini(
                        palette,
                        p.enabled ? 'ENABLED' : 'DISABLED',
                        () => studio.toggleProvider(p.id),
                        active: p.enabled,
                      ),
                      const SizedBox(width: 5),
                      _mini(
                        palette,
                        'CLEAR',
                        () => studio.clearKey(p.id),
                      ),
                      if (!p.isPreset) ...[
                        const SizedBox(width: 5),
                        _mini(
                          palette,
                          'DELETE',
                          () => studio.removeProvider(p.id),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        cors ? '◈ browser cors ok' : '◇ needs proxy on web',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 8,
                          color: cors ? palette.ok : palette.warn,
                        ),
                      ),
                      const Spacer(),
                      if (p.looksPlausible)
                        Text(
                          'plausible',
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8,
                            color: palette.ok,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    Palette palette, {
    required String label,
    required String initial,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              letterSpacing: 0.8,
              color: palette.dim,
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            initialValue: initial,
            onChanged: onChanged,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10,
              color: palette.bright,
            ),
            cursorColor: palette.bright,
            cursorWidth: 4,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                color: palette.dim.withValues(alpha: 0.7),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.mid),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mini(
    Palette palette,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? palette.mid : palette.line,
          ),
          color: active ? palette.mid.withValues(alpha: 0.13) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Future<void> _addCustomDialog(
    BuildContext context,
    StudioController studio,
    Palette palette,
  ) async {
    final label = TextEditingController();
    final baseUrl = TextEditingController(text: 'https://');
    final model = TextEditingController();
    final key = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierColor: palette.bg.withValues(alpha: 0.82),
      builder: (context) => Dialog(
        backgroundColor: palette.panel,
        shape: const RoundedRectangleBorder(),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: palette.mid),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'NEW OPENAI-COMPATIBLE ENDPOINT',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
              const SizedBox(height: 12),
              for (final f in [
                ('LABEL', label, 'my gateway'),
                ('BASE URL', baseUrl, 'https://host/v1'),
                ('MODEL', model, 'model-id'),
                ('API KEY', key, 'sk-…'),
              ]) ...[
                _field(
                  palette,
                  label: f.$1,
                  initial: f.$2.text,
                  hint: f.$3,
                  onChanged: (v) => f.$2.text = v,
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _mini(palette, 'CANCEL', () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  _mini(palette, 'ADD', () {
                    studio.addCustomProvider(
                      label: label.text,
                      baseUrl: baseUrl.text,
                      model: model.text,
                      apiKey: key.text,
                    );
                    Navigator.pop(context);
                  }, active: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    label.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }
}
