import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;

import '../../core/agent_runtime.dart';
import '../../core/palette.dart';
import '../../core/pi_bridge.dart';
import '../../state/studio_controller.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';

/// PI tab — the real `pi` CLI: version, update, model catalog, and the
/// per-agent binding between the fleet and Pi's own runtime.
class PiScreen extends StatefulWidget {
  const PiScreen({super.key});

  @override
  State<PiScreen> createState() => _PiScreenState();
}

class _PiScreenState extends State<PiScreen> {
  final TextEditingController _filter = TextEditingController();
  String _providerFilter = '';
  bool _showAllModels = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final studio = context.watch<StudioController>();
    final palette = term.palette;
    final pi = studio.pi;

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        _statusPanel(palette, studio),
        const SizedBox(height: 8),
        _updatePanel(palette, studio),
        const SizedBox(height: 8),
        _agentsPanel(palette, studio),
        const SizedBox(height: 8),
        _modelsPanel(palette, studio, pi),
      ],
    );
  }

  // ── PI RUNTIME ─────────────────────────────────────────────────────────

  Widget _statusPanel(Palette palette, StudioController studio) {
    final pi = studio.pi;
    final st = pi.status;
    final online = pi.connected;

    return TermPanel(
      palette: palette,
      title: 'PI RUNTIME',
      accent: online,
      trailing: _tag(
        palette,
        online ? 'ONLINE' : 'OFFLINE',
        online ? palette.ok : palette.warn,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(palette, 'binary', st.installed ?? 'not found'),
          _row(palette, 'node', '${st.node ?? '?'}  ${st.nodeOk ? 'ok' : 'too old (need 22.19+)'}'),
          _row(palette, 'models', '${st.modelCount} from live catalog'),
          _row(
            palette,
            'providers',
            st.providers.isEmpty ? 'none authenticated' : st.providers.join(', '),
          ),
          _row(palette, 'bridge', pi.baseUrl),
          if (st.agentDir.isNotEmpty) _row(palette, 'agent dir', st.agentDir),
          if (pi.lastCatalogRefresh != null)
            _row(palette, 'catalog', _ago(pi.lastCatalogRefresh!)),
          if (pi.lastError != null) ...[
            const SizedBox(height: 5),
            _note(palette, pi.lastError!, palette.warn),
          ],
          if (pi.activity.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: palette.mid,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    pi.activity,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9,
                      color: palette.mid,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _btn(
                palette,
                online ? 'RECONNECT' : 'CONNECT',
                () => studio.pi.connect(),
                active: !pi.busy,
              ),
              _btn(
                palette,
                'REFRESH MODELS',
                () => studio.pi.refreshModels(force: true),
              ),
              _btn(
                palette,
                'SYNC KEYS',
                () async {
                  final r = await studio.syncKeysToPi();
                  if (!context.mounted) return;
                  _toast(
                    r['ok'] == true
                        ? 'pi auth.json updated (${(r['providers'] as List?)?.length ?? 0} providers)'
                        : 'sync failed: ${r['error'] ?? 'unknown'}',
                    ok: r['ok'] == true,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── UPDATES ────────────────────────────────────────────────────────────

  Widget _updatePanel(Palette palette, StudioController studio) {
    final pi = studio.pi;
    final up = pi.update;
    final pending = up != null && up.updateAvailable;

    return TermPanel(
      palette: palette,
      title: 'UPDATE',
      trailing: _tag(
        palette,
        pending ? 'UPDATE' : (up == null ? 'UNKNOWN' : 'CURRENT'),
        pending ? palette.warn : palette.dim,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (up == null)
            _note(palette, 'no version probe yet', palette.dim)
          else
            _note(
              palette,
              up.summary,
              up.error != null
                  ? palette.warn
                  : (pending ? palette.warn : palette.ok),
            ),
          if (pi.lastUpdateRun != null)
            _row(palette, 'last update', _ago(pi.lastUpdateRun!)),
          _row(
            palette,
            'auto check',
            pi.autoUpdate
                ? 'every ${pi.autoUpdateInterval.inHours}h'
                : 'off',
            valueColor: pi.autoUpdate ? palette.ok : palette.dim,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _btn(
                palette,
                'CHECK',
                () => studio.pi.checkForUpdate(),
              ),
              _btn(
                palette,
                'REFRESH CATALOG',
                () => studio.pi.applyUpdate(target: 'models'),
              ),
              _btn(
                palette,
                pending ? 'INSTALL ${up.latest}' : 'REINSTALL PI',
                () async {
                  final r = await studio.pi.applyUpdate(target: 'self');
                  if (!context.mounted) return;
                  _toast(
                    r['ok'] == true
                        ? 'pi updated to ${(r['installed'] ?? '')}'
                        : 'update failed: ${r['error'] ?? r['stderr'] ?? 'unknown'}',
                    ok: r['ok'] == true,
                  );
                },
                active: pending || up?.latest != null,
              ),
              _btn(
                palette,
                pi.autoUpdate ? 'AUTO: ON' : 'AUTO: OFF',
                () {
                  studio.pi.setAutoUpdate(!pi.autoUpdate);
                  setState(() {});
                },
                active: pi.autoUpdate,
              ),
            ],
          ),
          const SizedBox(height: 5),
          _note(
            palette,
            'auto-update checks every ${pi.autoUpdateInterval.inHours}h and '
            'refreshes the catalog; installing a new binary is always a '
            'manual action.',
            palette.dim,
          ),
        ],
      ),
    );
  }

  // ── FLEET BINDING ──────────────────────────────────────────────────────

  Widget _agentsPanel(Palette palette, StudioController studio) {
    final pi = studio.pi;
    final ready = studio.piModels();

    return TermPanel(
      palette: palette,
      title: 'FLEET → PI',
      trailing: Text(
        '${studio.agents.where((a) => a.engine == AgentEngine.pi).length}'
        '/${studio.agents.length} on pi',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          letterSpacing: 0.8,
          color: palette.dim,
        ),
      ),
      child: Column(
        children: [
          for (final a in studio.agents) ...[
            _agentRow(palette, studio, a, ready, pi.connected),
            const SizedBox(height: 5),
          ],
          const SizedBox(height: 2),
          _note(
            palette,
            pi.connected
                ? 'Pi agents get pi\'s own tools (read, bash, edit, write) and '
                    'the live model catalog. Local agents use the sky toolset.'
                : 'connect the bridge to run agents on real pi.',
            palette.dim,
          ),
        ],
      ),
    );
  }

  Widget _agentRow(
    Palette palette,
    StudioController studio,
    AgentRuntime a,
    List<PiModel> ready,
    bool online,
  ) {
    final onPi = a.engine == AgentEngine.pi;
    final color = _agentColor(palette, a.colorIndex);

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 2),
          top: BorderSide(color: palette.line),
          right: BorderSide(color: palette.line),
          bottom: BorderSide(color: palette.line),
        ),
        color: palette.bg.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                a.name,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: palette.bright,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  onPi ? (a.piModel.isEmpty ? 'pi · default model' : 'pi · ${a.piModel}') : 'local loop',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: onPi ? palette.mid : palette.dim,
                  ),
                ),
              ),
              _btn(
                palette,
                onPi ? 'PI' : 'LOCAL',
                () => studio.bindAgentToPi(a.id, enabled: !onPi),
                active: onPi && online,
              ),
            ],
          ),
          if (onPi) ...[
            const SizedBox(height: 5),
            SizedBox(
              height: 22,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in (ready.isEmpty
                          ? const <PiModel>[]
                          : ready.take(14)))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () => studio.bindAgentToPi(
                          a.id,
                          enabled: true,
                          model: m.qualifiedId,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: a.piModel == m.qualifiedId
                                  ? palette.bright
                                  : palette.line,
                            ),
                          ),
                          child: Text(
                            m.id,
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 8,
                              color: a.piModel == m.qualifiedId
                                  ? palette.bright
                                  : palette.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── MODEL CATALOG ──────────────────────────────────────────────────────

  Widget _modelsPanel(Palette palette, StudioController studio, dynamic pi) {
    final all = studio.pi.models;
    final providers = <String>{
      for (final m in all) if (m.provider.isNotEmpty) m.provider,
    }.toList()
      ..sort();

    final query = _filter.text.trim();
    var shown = studio.piModels(query);
    if (_providerFilter.isNotEmpty) {
      shown = shown.where((m) => m.provider == _providerFilter).toList();
    }
    final limit = _showAllModels ? shown.length : 18;

    return TermPanel(
      palette: palette,
      title: 'MODEL CATALOG',
      trailing: Text(
        '${shown.length}/${all.length}',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          letterSpacing: 0.8,
          color: palette.dim,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10,
              color: palette.bright,
            ),
            cursorColor: palette.bright,
            cursorWidth: 4,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'filter models…',
              hintStyle: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9.5,
                color: palette.dim,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 6,
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
          const SizedBox(height: 6),
          SizedBox(
            height: 22,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip(palette, 'ALL', _providerFilter.isEmpty, () {
                  setState(() => _providerFilter = '');
                }),
                for (final p in providers)
                  _chip(palette, p.toUpperCase(), _providerFilter == p, () {
                    setState(() => _providerFilter = p);
                  }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (all.isEmpty)
            _note(
              palette,
              'no models — is the bridge connected?',
              palette.dim,
            )
          else
            for (final m in shown.take(limit)) ...[
              // A model is usable only when pi has a credential for its provider.
              _modelRow(
                palette,
                m,
                hasKey: studio.pi.hasCredential(m.provider),
              ),
              const SizedBox(height: 3),
            ],
          if (shown.length > limit) ...[
            const SizedBox(height: 4),
            _btn(
              palette,
              'SHOW ALL ${shown.length}',
              () => setState(() => _showAllModels = true),
            ),
          ] else if (_showAllModels && shown.length > 18) ...[
            const SizedBox(height: 4),
            _btn(
              palette,
              'COLLAPSE',
              () => setState(() => _showAllModels = false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modelRow(Palette palette, PiModel m, {bool hasKey = false}) {
    return Row(
      children: [
        Text(
          m.reasoning ? '◈' : '◇',
          style: TextStyle(
            fontSize: 8,
            color: hasKey ? palette.ok : palette.dim,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            m.id,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9,
              color: palette.bright,
            ),
          ),
        ),
        if (m.supportsImages)
          Text(
            'IMG ',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7.5,
              color: palette.mid,
            ),
          ),
        Text(
          m.contextWindow == null ? '' : '${(m.contextWindow! / 1000).round()}k ',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            color: palette.dim,
          ),
        ),
        Text(
          m.provider,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            letterSpacing: 0.5,
            color: palette.dim,
          ),
        ),
      ],
    );
  }

  // ── small widgets ──────────────────────────────────────────────────────

  Widget _row(Palette palette, String k, String v, {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 66,
              child: Text(
                k,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  letterSpacing: 0.7,
                  color: palette.dim,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9,
                  color: valueColor ?? palette.bright,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _note(Palette palette, String text, Color color) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          height: 1.35,
          color: color,
        ),
      );

  Widget _tag(Palette palette, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          color: color.withValues(alpha: 0.08),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7.5,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  Widget _btn(
    Palette palette,
    String label,
    VoidCallback onTap, {
    bool active = true,
  }) {
    final color = active ? palette.mid : palette.line;
    return InkWell(
      onTap: active ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: color)),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Widget _chip(Palette palette, String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: active ? palette.bright : palette.line),
            color: active
                ? palette.mid.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              letterSpacing: 0.6,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? palette.bright : palette.dim,
            ),
          ),
        ),
      ),
    );
  }

  Color _agentColor(Palette p, int i) {
    const fallback = [
      Color(0xFF7CFFC4),
      Color(0xFF7CC4FF),
      Color(0xFFFFD77C),
      Color(0xFFFF7CD0),
    ];
    return i >= 0 && i < fallback.length ? fallback[i] : p.mid;
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    final palette = context.read<TerminalController>().palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: palette.panel,
        content: Text(
          msg,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 10,
            color: ok ? palette.bright : palette.warn,
          ),
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
