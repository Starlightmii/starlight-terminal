import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;

import '../../core/palette.dart';
import '../../core/providers.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// Provider configuration: paste keys, pick models, add custom endpoints.
///
/// Two things this screen had to get right after the last round of feedback:
///
///  * **Reveal must actually reveal.** The old field was a `TextFormField` with
///    `initialValue`, which cannot be updated after first build, so "SHOW KEYS"
///    did nothing and — worse — re-typing a key looked like it had been lost.
///  * **A key is only useful if its models are reachable.** Each card now shows
///    how many models that provider contributes to the pi catalog, offers a
///    searchable picker, and can confirm the key against the provider's own
///    `/models` endpoint.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  ProviderKind _filter = ProviderKind.llm;
  final Set<String> _expanded = <String>{};
  final Map<String, TextEditingController> _keyCtl = <String, TextEditingController>{};
  final Map<String, TextEditingController> _modelCtl = <String, TextEditingController>{};
  final Map<String, TextEditingController> _urlCtl = <String, TextEditingController>{};
  bool _showKey = false;
  String _search = '';
  String? _busy;

  @override
  void dispose() {
    for (final c in _keyCtl.values) {
      c.dispose();
    }
    for (final c in _modelCtl.values) {
      c.dispose();
    }
    for (final c in _urlCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(
    Map<String, TextEditingController> map,
    String id,
    String initial,
  ) {
    final c = map.putIfAbsent(id, () => TextEditingController(text: initial));
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final all = studio.ofKind(_filter);
    final list = _search.isEmpty
        ? all
        : all
            .where((p) =>
                p.label.toLowerCase().contains(_search.toLowerCase()) ||
                p.id.toLowerCase().contains(_search.toLowerCase()) ||
                p.model.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      children: [
        _summary(studio, palette),
        const SizedBox(height: 8),
        _filterBar(studio, palette),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: '${_filter.name.toUpperCase()} PROVIDERS · ${list.length}',
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
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _search.isEmpty
                          ? 'no providers of this kind'
                          : 'no provider matching "$_search"',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 10,
                        color: palette.dim,
                      ),
                    ),
                  )
                : ListView.separated(
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

  // ── Summary ────────────────────────────────────────────────────────────

  Widget _summary(StudioController studio, Palette palette) {
    final total = studio.providers.length;
    final ready = studio.configuredCount;
    final catalog = studio.pi.models.length;
    final keyedIds = studio.agentProviders.map((p) => p.id).toSet();
    final keyedModels =
        studio.pi.models.where((m) => keyedIds.contains(m.providerId)).length;
    final providersInCatalog =
        studio.pi.models.map((m) => m.providerId).toSet().length;
    // "37 models" with zero keys read as a lie: those ids are preset guesses,
    // not rows the provider agreed to serve. Say which is which.
    final summaryLine = ready == 0
        ? '$total providers · 0 keys · $catalog preset ids from '
            '$providersInCatalog vendors (unconfirmed — add a key)'
        : '$ready of $total providers ready · $keyedModels callable · '
            '$catalog in the pi catalog';

    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  summaryLine,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9,
                    color: palette.dim,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _mini(palette, '✓ VALIDATE', () {
                      final r = studio.agentProviders;
                      _toast(
                        r.isEmpty
                            ? 'no usable LLM key yet — paste one below'
                            : '${r.length} provider${r.length == 1 ? '' : 's'} ready · '
                                'pi uses ${r.first.id}',
                        palette,
                      );
                    }),
                    const SizedBox(width: 6),
                    _mini(
                      palette,
                      _busy == 'probe' ? 'PROBING…' : 'REFRESH MODELS',
                      _busy == 'probe'
                          ? () {}
                          : () async {
                              setState(() => _busy = 'probe');
                              final report = await studio.pi
                                  .probeProviders(studio.providers);
                              studio.appLog
                                  .info('models · ${report.summary()}', scope: 'keys');
                              if (!mounted) return;
                              setState(() => _busy = null);
                              _toast(report.summary(), palette);
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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

  void _toast(String msg, Palette palette) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'Mono', fontSize: 11),
        ),
        backgroundColor: palette.panel,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _filterBar(StudioController studio, Palette palette) {
    return Column(
      children: [
        Row(
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
              onTap: () {
                setState(() {
                  _showKey = !_showKey;
                  // Rebuild the controllers from the store so reveal/hide is
                  // authoritative rather than a stale `initialValue`.
                  if (_showKey) {
                    _keyCtl.clear();
                  } else {
                    _keyCtl.clear();
                  }
                });
              },
              child: Text(
                _showKey ? 'HIDE KEYS' : 'SHOW KEYS',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: _showKey ? palette.warn : palette.dim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10.5,
              color: palette.bright,
            ),
            cursorColor: palette.bright,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 14, color: palette.dim),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 24, minHeight: 0),
              hintText: 'filter providers by name, id or model',
              hintStyle:
                  TextStyle(fontFamily: 'Mono', fontSize: 9.5, color: palette.dim),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: palette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: palette.mid),
              ),
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

  // ── Provider card ──────────────────────────────────────────────────────

  Widget _providerCard(
    BuildContext context,
    StudioController studio,
    Palette palette,
    Provider p,
  ) {
    final open = _expanded.contains(p.id);
    final cors = ProviderPresets.typicallyAllowsBrowserCors(p);
    final usable = p.ready && p.looksPlausible;
    final modelCount =
        studio.pi.models.where((m) => m.providerId == p.id).length;
    final isPiActive = studio.agentProvider?.id == p.id;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: usable ? palette.mid : palette.line),
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
                    usable ? '●' : '○',
                    style: TextStyle(
                      fontSize: 9,
                      color: usable ? palette.ok : palette.dim,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Mono',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      p.enabled ? palette.bright : palette.dim,
                                ),
                              ),
                            ),
                            if (isPiActive) ...[
                              const SizedBox(width: 5),
                              _tag(palette, 'PI', palette.ok),
                            ],
                          ],
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _showKey ? (p.apiKey.isEmpty ? '—' : p.apiKey) : p.maskedKey,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 8,
                          color: p.apiKey.isEmpty ? palette.dim : palette.mid,
                        ),
                      ),
                      Text(
                        '$modelCount models',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 7.5,
                          color: modelCount > 0 ? palette.ok : palette.dim,
                        ),
                      ),
                    ],
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    palette,
                    label: 'API KEY',
                    controller: _ctl(
                      _keyCtl,
                      '${p.id}|$_showKey|${p.apiKey}',
                      _showKey ? p.apiKey : '',
                    ),
                    hint: _showKey ? 'paste key' : 'secret hidden — tap SHOW KEYS',
                    mono: false,
                    obscure: !_showKey,
                    onChanged: (v) => studio.setKey(p.id, v),
                  ),
                  const SizedBox(height: 5),
                  _field(
                    palette,
                    label: 'MODEL',
                    controller: _ctl(_modelCtl, '${p.id}|${p.model}', p.model),
                    hint: 'model id',
                    onChanged: (v) => studio.setModel(p.id, v),
                  ),
                  if (ProviderPresets.suggestionsFor(p.id).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _suggestions(studio, palette, p),
                  ],
                  if (modelCount > 0) ...[
                    const SizedBox(height: 4),
                    _catalogChips(studio, palette, p),
                  ],
                  const SizedBox(height: 5),
                  _field(
                    palette,
                    label: 'BASE URL',
                    controller: _ctl(_urlCtl, '${p.id}|${p.baseUrl}', p.baseUrl),
                    hint: 'https://…/v1',
                    onChanged: (v) => studio.setBaseUrl(p.id, v),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      _mini(
                        palette,
                        p.enabled ? 'ENABLED' : 'DISABLED',
                        () {
                          studio.toggleProvider(p.id);
                          setState(() {});
                        },
                        active: p.enabled,
                      ),
                      _mini(
                        palette,
                        'CLEAR KEY',
                        () {
                          studio.clearKey(p.id);
                          _keyCtl.clear();
                          setState(() {});
                        },
                      ),
                      _mini(
                        palette,
                        isPiActive ? 'IN USE BY PI' : 'USE FOR PI',
                        !usable
                            ? () => _toast(
                                  '${p.label} needs a plausible key first',
                                  palette,
                                )
                            : () {
                                studio.setPiProvider(p.id);
                                _toast(
                                  'pi now routes through ${p.label} · ${p.model}',
                                  palette,
                                );
                                setState(() {});
                              },
                        active: isPiActive,
                      ),
                      _mini(
                        palette,
                        _busy == p.id ? 'TESTING…' : 'TEST KEY',
                        () async {
                          setState(() => _busy = p.id);
                          final report =
                              await studio.pi.probeProviders([p]);
                          if (!mounted) return;
                          setState(() => _busy = null);
                          studio.appLog.info(
                            'keys test ${p.id} · ${report.summary()}',
                            scope: 'keys',
                          );
                          _toast(
                            report.ok
                                ? '${p.label}: ${report.counts[p.id]} models confirmed'
                                : '${p.label}: ${report.failed[p.id] ?? 'no key'}',
                            palette,
                          );
                        },
                      ),
                      if (!p.isPreset)
                        _mini(
                          palette,
                          'DELETE',
                          () {
                            studio.removeProvider(p.id);
                            setState(() {});
                          },
                        ),
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
                        )
                      else if (p.apiKey.isNotEmpty)
                        Text(
                          'too short / placeholder',
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8,
                            color: palette.warn,
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

  Widget _tag(Palette p, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: 0.10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  Widget _suggestions(StudioController studio, Palette palette, Provider p) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final m in ProviderPresets.suggestionsFor(p.id))
          InkWell(
            onTap: () {
              studio.setModel(p.id, m);
              _modelCtl.clear();
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: p.model == m ? palette.bright : palette.line,
                ),
                color: p.model == m
                    ? palette.bright.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: Text(
                ProviderPresets.freeModels.contains(m) ? '$m ·free' : m,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 7,
                  color: p.model == m
                      ? palette.bright
                      : (ProviderPresets.freeModels.contains(m)
                          ? palette.ok
                          : palette.dim),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Every catalog entry this provider contributes, so the operator can see the
  /// key actually produced models instead of trusting a green dot.
  Widget _catalogChips(
    StudioController studio,
    Palette palette,
    Provider p,
  ) {
    final entries =
        studio.pi.models.where((m) => m.providerId == p.id).take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IN THE PI CATALOG · $entries.length'
          '${studio.pi.probedProviders.contains(p.id) ? ' · confirmed' : ' · unconfirmed'}',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7.5,
            letterSpacing: 0.8,
            color: palette.dim,
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final m in entries)
              InkWell(
                onTap: () {
                  studio.pi.setModel(m.id);
                  studio.setModel(p.id, m.id);
                  _modelCtl.clear();
                  _toast('${p.label} model → ${m.id}', palette);
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: m.id == studio.pi.activeModel
                          ? palette.ok
                          : palette.line,
                    ),
                  ),
                  child: Text(
                    m.id,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7,
                      color: m.id == studio.pi.activeModel
                          ? palette.ok
                          : palette.dim,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    Palette palette, {
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    bool obscure = false,
    bool mono = true,
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
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: mono ? 10 : 9.5,
              letterSpacing: mono ? 0 : 0.4,
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
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: palette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
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
          border: Border.all(color: active ? palette.mid : palette.line),
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
          decoration: BoxDecoration(border: Border.all(color: palette.mid)),
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
                  controller: f.$2,
                  hint: f.$3,
                  onChanged: (_) {},
                  obscure: f.$1 == 'API KEY',
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
                    setState(() {});
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
