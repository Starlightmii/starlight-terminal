import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../core/pi_bridge.dart';
import '../../core/session_store.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// The Pi workbench: a real conversation with the installed `pi` CLI, plus the
/// runtime/update/catalog controls and the fleet binding panel.
///
/// Two layouts, one screen: a full chat terminal when the bridge is live, and a
/// diagnostics-first layout when it is not, because a dead bridge with an empty
/// transcript is the least useful thing this app could show.
class PiScreen extends StatefulWidget {
  const PiScreen({super.key});

  @override
  State<PiScreen> createState() => _PiScreenState();
}

class _PiScreenState extends State<PiScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _modelFilter = TextEditingController();

  String _filter = '';
  bool _showCatalog = false;
  bool _showRuntime = true;
  String? _streamingId;
  bool _sending = false;
  int _streamed = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _modelFilter.dispose();
    super.dispose();
  }

  void _snapToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(StudioController studio) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();

    final session = studio.sessions.ensurePi();
    studio.sessions.appendMessage(
      session.id,
      SessionMessage(role: 'you', text: text, at: DateTime.now()),
      remember: true,
    );
    studio.appLog.info('prompt → pi', scope: 'pi');

    setState(() {
      _sending = true;
      _streamed = 0;
      _streamingId = session.id;
    });
    _snapToBottom();

    try {
      await for (final e in studio.pi.converse(text)) {
        _ingest(studio, session, e);
      }
    } catch (e) {
      studio.sessions.appendMessage(
        session.id,
        SessionMessage(
          role: 'sys',
          text: 'pi error: $e',
          at: DateTime.now(),
          isError: true,
        ),
      );
      studio.appLog.error('$e', scope: 'pi');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _streamingId = null;
        });
      }
      _snapToBottom();
    }
  }

  /// Applies one Pi event to the transcript. Text deltas are coalesced into a
  /// single streaming message rather than appended per token, which keeps the
  /// list from thrashing on a long generation.
  void _ingest(StudioController studio, ChatSession session, PiEvent e) {
    switch (e.kind) {
      case 'text_delta':
        final chunk = e.deltaText;
        if (chunk.isEmpty) return;
        if (_streamingId == null) {
          // Start a fresh assistant bubble.
          _streamed = session.messages.length;
        }
        _streamed += chunk.length;
        studio.sessions.appendMessage(
          session.id,
          SessionMessage(role: 'pi', text: chunk, at: DateTime.now()),
        );
        if (_streamed % 400 < chunk.length) _snapToBottom();
      case 'thinking_delta':
        // Reasoning is useful in the LOG, but noisy in the transcript.
        studio.appLog.debug(e.deltaText, scope: 'pi.think');
      case 'tool_start':
        studio.sessions.appendMessage(
          session.id,
          SessionMessage(
            role: 'tool',
            text: '${e.toolName ?? 'tool'} ${e.toolArgs ?? ''}'.trim(),
            at: DateTime.now(),
            toolName: e.toolName,
          ),
        );
        _snapToBottom();
      case 'tool_end':
        if ((e.text ?? '').trim().isNotEmpty) {
          studio.sessions.appendMessage(
            session.id,
            SessionMessage(
              role: 'tool',
              text: e.text!.trim(),
              at: DateTime.now(),
              toolName: e.toolName,
            ),
          );
        }
      case 'error':
        studio.sessions.appendMessage(
          session.id,
          SessionMessage(
            role: 'sys',
            text: e.text ?? 'pi reported an error',
            at: DateTime.now(),
            isError: true,
          ),
        );
      case 'message':
        final t = (e.text ?? '').trim();
        if (t.isNotEmpty) {
          studio.sessions.appendMessage(
            session.id,
            SessionMessage(role: 'pi', text: t, at: DateTime.now()),
            remember: true,
          );
        }
    }
  }

  Future<void> _abort(StudioController studio) async {
    await studio.pi.abortAgent();
    studio.appLog.warn('abort requested', scope: 'pi');
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final pi = studio.pi;
    final session = studio.sessions.ensurePi(model: pi.selectedModel);

    return Column(
      children: [
        _statusBar(studio, palette),
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: TermPanel(
                  palette: palette,
                  title: 'PI TERMINAL',
                  accent: true,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniBtn(
                        palette,
                        session.pinned ? 'PINNED' : 'PIN',
                        () {
                          session.pinned = !session.pinned;
                          setState(() {});
                        },
                        active: session.pinned,
                      ),
                      const SizedBox(width: 4),
                      _miniBtn(palette, 'NEW', () {
                        studio.sessions.create(
                          kind: SessionKind.pi,
                          title: 'pi session',
                        );
                        setState(() {});
                      }),
                      const SizedBox(width: 4),
                      _miniBtn(
                        palette,
                        _showCatalog ? 'HIDE MODELS' : 'MODELS',
                        () => setState(() => _showCatalog = !_showCatalog),
                        active: _showCatalog,
                      ),
                    ],
                  ),
                  child: _showCatalog
                      ? _catalog(palette, studio)
                      : _transcript(palette, studio, session),
                ),
              ),
              const SizedBox(height: 8),
              _composer(palette, studio, session),
            ],
          ),
        ),
      ],
    );
  }

  // ── status bar ─────────────────────────────────────────────────────────

  Widget _statusBar(StudioController studio, Palette palette) {
    final pi = studio.pi;
    final up = pi.update;
    final pending = up != null && up.updateAvailable;

    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                pi.connected ? '●' : '○',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  color: pi.connected ? palette.ok : palette.err,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                pi.connected ? 'PI ONLINE' : 'PI OFFLINE',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: pi.connected ? palette.bright : palette.err,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${pi.status.versionLabel} · '
                  '${pi.models.length} models · '
                  '${pi.selectedModel.isEmpty ? 'default model' : pi.selectedModel}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
              ),
              const Spacer(),
              if (pending)
                _tag(palette, '↑ ${up.latest}', palette.warn),
            ],
          ),
          if (!pi.connected) ...[
            const SizedBox(height: 5),
            Text(
              pi.lastError ??
                  'bridge unreachable — start it with: '
                      'node /home/user/pi-bridge/server.mjs',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                height: 1.35,
                color: palette.err,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _miniBtn(palette, 'RECONNECT', () => studio.pi.connect()),
              _miniBtn(
                palette,
                'SYNC KEYS',
                () async {
                  final r = await studio.syncKeysToPi();
                  if (!mounted) return;
                  _toast(
                    r['ok'] == true
                        ? 'pushed ${r['pushed'] ?? 0} keys into pi'
                        : 'sync failed: ${r['error'] ?? 'unreachable'}',
                    ok: r['ok'] == true,
                  );
                },
              ),
              _miniBtn(
                palette,
                'CHECK',
                () => studio.pi.checkForUpdate(),
              ),
              _miniBtn(
                palette,
                pending ? 'INSTALL ${up.latest}' : 'UPDATE PI',
                () async {
                  final r = await studio.pi.applyUpdate(target: 'self');
                  if (!mounted) return;
                  _toast(
                    r['ok'] == true
                        ? 'pi updated · ${r['installed'] ?? ''}'
                        : 'update failed: ${r['error'] ?? r['stderr'] ?? '?'}',
                    ok: r['ok'] == true,
                  );
                },
                active: pending,
              ),
              _miniBtn(
                palette,
                'CATALOG',
                () => studio.pi.applyUpdate(target: 'models'),
              ),
              _miniBtn(
                palette,
                pi.autoUpdate ? 'AUTO ✓' : 'AUTO ✗',
                () {
                  studio.pi.setAutoUpdate(!pi.autoUpdate);
                  setState(() {});
                },
                active: pi.autoUpdate,
              ),
              _miniBtn(
                palette,
                _showRuntime ? 'DIAG' : 'FLEET',
                () => setState(() => _showRuntime = !_showRuntime),
                active: _showRuntime,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── transcript ─────────────────────────────────────────────────────────

  Widget _transcript(
    Palette palette,
    StudioController studio,
    ChatSession session,
  ) {
    if (studio.pi.connected && _showRuntime) {
      return Column(
        children: [
          Expanded(child: _messages(palette, session)),
          const SizedBox(height: 6),
          _fleetStrip(palette, studio),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: _messages(palette, session)),
      ],
    );
  }

  Widget _messages(Palette palette, ChatSession session) {
    if (session.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'π',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 34,
                  color: palette.bright.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Talk to the real pi coding agent.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: palette.mid,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'It has its own tools — read, bash, edit, write — and the '
                'live model catalog. Every exchange becomes a memory.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  height: 1.45,
                  color: palette.dim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: session.messages.length,
      itemBuilder: (context, i) {
        final m = session.messages[i];
        final color = switch (m.role) {
          'you' => palette.bright,
          'pi' => palette.mid,
          'tool' => palette.warn,
          _ => m.isError ? palette.err : palette.dim,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 14,
                child: Text(
                  m.glyph,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9.5,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  m.text,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9,
                    height: 1.45,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fleetStrip(Palette palette, StudioController studio) {
    final onPi = studio.agents.where((a) => a.enabled).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Text(
            'FLEET → PI  $onPi/${studio.agents.length}',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: palette.dim,
            ),
          ),
          const Spacer(),
          for (final a in studio.agents.take(4))
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: () {
                  studio.bindAgentToPi(
                    a.id,
                    enabled: !a.enabled,
                    model: studio.pi.selectedModel,
                  );
                  setState(() {});
                },
                child: Text(
                  '${a.enabled ? '◉' : '○'}${a.name.substring(0, 3)}',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8,
                    color: a.enabled ? palette.ok : palette.dim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── composer ───────────────────────────────────────────────────────────

  Widget _composer(
    Palette palette,
    StudioController studio,
    ChatSession session,
  ) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '❯',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11,
                  color: palette.bright,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _input,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 10,
                    color: palette.bright,
                  ),
                  cursorColor: palette.bright,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(studio),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: _sending
                        ? 'pi is working…'
                        : 'instruct pi — code, files, commands, questions',
                    hintStyle: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9.5,
                      color: palette.dim,
                    ),
                  ),
                ),
              ),
              if (_sending)
                InkWell(
                  onTap: () => _abort(studio),
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.err),
                    ),
                    child: Text(
                      'STOP',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: palette.err,
                      ),
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () => _send(studio),
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.bright),
                      color: palette.bright.withValues(alpha: 0.08),
                    ),
                    child: Text(
                      'SEND',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: palette.bright,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${session.messageCount} msg · '
                '${session.toolCalls} tools · '
                '${session.ageLabel}',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 7.5,
                  color: palette.dim,
                ),
              ),
              const Spacer(),
              if (studio.pi.connected && studio.pi.selectedModel.isNotEmpty)
                Text(
                  studio.pi.selectedModel,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 7.5,
                    color: palette.mid,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── model catalog ──────────────────────────────────────────────────────

  Widget _catalog(Palette palette, StudioController studio) {
    final models = studio.piModels(_filter);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _modelFilter,
                onChanged: (v) => setState(() => _filter = v),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9,
                  color: palette.bright,
                ),
                cursorColor: palette.bright,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'filter ${studio.pi.models.length} models…',
                  hintStyle: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9,
                    color: palette.dim,
                  ),
                ),
              ),
            ),
            Text(
              '${models.length}',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.dim,
              ),
            ),
          ],
        ),
        Divider(color: palette.line, height: 8),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: models.length,
            itemBuilder: (context, i) {
              final m = models[i];
              final selected = studio.pi.selectedModel == m.qualifiedId;
              final hasKey = studio.pi.hasCredential(m.provider);
              return InkWell(
                onTap: () async {
                  await studio.pi.selectModel(m.qualifiedId);
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        selected ? '◉' : (hasKey ? '○' : '·'),
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 8.5,
                          color: selected
                              ? palette.ok
                              : (hasKey ? palette.mid : palette.dim),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          m.id,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8.5,
                            color: selected ? palette.bright : palette.mid,
                          ),
                        ),
                      ),
                      if (m.supportsImages)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            'IMG',
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 7,
                              color: palette.warn,
                            ),
                          ),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        m.shortContext,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 7,
                          color: palette.dim,
                        ),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 52,
                        child: Text(
                          m.provider,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 7,
                            color: palette.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── small widgets ──────────────────────────────────────────────────────

  Widget _miniBtn(
    Palette palette,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? palette.bright : palette.line,
          ),
          color: active
              ? palette.bright.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7.5,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w700,
            color: active ? palette.bright : palette.mid,
          ),
        ),
      ),
    );
  }

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
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Mono')),
        duration: const Duration(seconds: 3),
        backgroundColor: ok ? null : Colors.red.shade900,
      ),
    );
  }
}
