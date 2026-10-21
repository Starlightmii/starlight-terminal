import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/model_client.dart';
import '../../core/palette.dart';
import '../../core/pi_core.dart';
import '../../core/providers.dart';
import '../../core/session_store.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// The pi workbench: a terminal that runs `pi` sessions.
///
/// There is deliberately no "connect"/"reconnect"/"sync keys" here. Previous
/// builds talked to a loopback HTTP broker which cannot exist on a phone, so
/// those controls could never have worked. This screen behaves like a shell:
/// you type commands, `pi` answers, and the transcript is the session.
class PiScreen extends StatefulWidget {
  const PiScreen({super.key});

  @override
  State<PiScreen> createState() => _PiScreenState();
}

class _PiScreenState extends State<PiScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Line> _lines = <_Line>[];
  bool _running = false;
  String? _sessionId;

  static const List<String> _commands = [
    'pi',
    'pi status',
    'pi update',
    'pi install',
    'pi models',
    'pi model <n>',
    'pi new',
    'pi clear',
    'pi help',
    'help',
    'clear',
  ];

  @override
  void initState() {
    super.initState();
    _lines.add(_Line.out(
      'pi terminal ready. Type `pi help` for commands.\n'
      'A prompt runs the agent over your best configured provider.',
      kind: _Kind.sys,
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _append(_Line l) {
    setState(() => _lines.add(l));
    _snap();
  }

  Future<void> _submit(StudioController studio) async {
    final raw = _input.text.trim();
    if (raw.isEmpty || _running) return;
    _input.clear();
    _append(_Line.cmd(raw));

    final pi = studio.pi;
    final lower = raw.toLowerCase();

    // ── built-ins ────────────────────────────────────────────────────────
    if (lower == 'help' || lower == 'pi help') {
      _append(_Line.out(
        'commands\n'
        '  pi status      install state, version, active model\n'
        '  pi install     provision the agent core\n'
        '  pi update      check npm for a newer release and apply it\n'
        '  pi models      list models the agent can drive\n'
        '  pi model <n>   switch the active model\n'
        '  pi new         start a fresh session\n'
        '  pi clear       clear this terminal\n'
        '  <text>         any other input is sent to the agent\n',
        kind: _Kind.sys,
      ));
      return;
    }
    if (lower == 'clear' || lower == 'pi clear') {
      setState(() => _lines.clear());
      return;
    }
    if (lower == 'pi status') {
      _append(_Line.out(
        'state     ${pi.statusLabel}\n'
        'installed ${pi.installedVersion.isEmpty ? '—' : pi.installedVersion}\n'
        'latest    ${pi.latestVersion.isEmpty ? '—' : pi.latestVersion}\n'
        'model     ${pi.activeModel.isEmpty ? '—' : pi.activeModel}\n'
        'provider  ${studio.agentProvider?.id ?? 'none configured'}\n'
        'session   ${_sessionId ?? '—'}',
        kind: _Kind.sys,
      ));
      return;
    }
    if (lower == 'pi install') {
      setState(() => _running = true);
      await pi.install();
      setState(() => _running = false);
      _append(_Line.out(pi.statusLabel, kind: _Kind.sys));
      return;
    }
    if (lower == 'pi update' || lower == 'pi upgrade') {
      setState(() => _running = true);
      final msg = await pi.update();
      setState(() => _running = false);
      studio.appLog.info(msg, scope: 'pi');
      _append(_Line.out(msg, kind: _Kind.sys));
      return;
    }
    if (lower == 'pi models') {
      _append(_Line.out(await pi.listModels(), kind: _Kind.sys));
      return;
    }
    if (lower.startsWith('pi model ')) {
      final n = int.tryParse(lower.substring(9).trim());
      if (n == null || n < 1 || n > pi.models.length) {
        _append(_Line.out('no such model index', kind: _Kind.err));
        return;
      }
      pi.selectByIndex(n - 1);
      _append(_Line.out('active model → ${pi.activeModel}', kind: _Kind.sys));
      return;
    }
    if (lower == 'pi new') {
      final s = studio.sessions.create(kind: SessionKind.pi, title: 'pi session');
      studio.sessions.setActive(s.id);
      setState(() {
        _sessionId = s.id;
        _lines.clear();
      });
      _append(_Line.out('new session ${s.id}', kind: _Kind.sys));
      return;
    }

    // ── a real agent turn ────────────────────────────────────────────────
    final provider = studio.agentProvider;
    if (provider == null) {
      _append(_Line.out(
        'no usable LLM key. Add one in KEYS — the agent runs on your own key, '
        'there is no bundled model.',
        kind: _Kind.err,
      ));
      return;
    }
    if (!studio.piOnline) {
      _append(_Line.out('pi is not installed — run `pi install`', kind: _Kind.err));
      return;
    }

    final session = studio.sessions.ensurePi(
      model: pi.activeModel,
    );
    _sessionId ??= session.id;
    studio.sessions.appendMessage(
      session.id,
      SessionMessage(role: 'you', text: raw, at: DateTime.now()),
      remember: true,
    );

    setState(() => _running = true);
    final buf = StringBuffer();
    _append(_Line.out('', kind: _Kind.agent, streaming: true));
    try {
      await for (final c in studio.models.stream(
        provider: provider,
        messages: _history(studio, session.id, raw),
        model: pi.activeModel.isEmpty ? null : pi.activeModel,
        system: 'You are pi, a coding agent running inside Starlight Terminal. '
            'Answer concisely; use plain text; no markdown tables.',
      )) {
        if (c.kind == ChunkKind.text) {
          buf.write(c.text);
          setState(() {
            _lines[_lines.length - 1] = _Line.out(buf.toString(), kind: _Kind.agent);
          });
          _snap();
        } else if (c.kind == ChunkKind.error) {
          setState(() {
            _lines[_lines.length - 1] = _Line.out(c.text, kind: _Kind.err);
          });
          studio.appLog.error(c.text, scope: 'pi');
        }
      }
    } catch (e) {
      _append(_Line.out('$e', kind: _Kind.err));
    } finally {
      setState(() => _running = false);
    }

    final reply = buf.toString().trim();
    if (reply.isNotEmpty) {
      studio.sessions.appendMessage(
        session.id,
        SessionMessage(role: 'pi', text: reply, at: DateTime.now()),
        remember: true,
      );
      studio.appLog.info('pi turn · ${reply.length} chars', scope: 'pi');
    }
  }

  List<Map<String, String>> _history(
    StudioController studio,
    String sessionId,
    String prompt,
  ) {
    final out = <Map<String, String>>[];
    final msgs = studio.sessions.byId(sessionId)?.messages ?? const [];
    for (final m in msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs) {
      if (m.isError) continue;
      out.add({
        'role': m.role == 'you' ? 'user' : 'assistant',
        'content': m.text,
      });
    }
    if (out.isEmpty || out.last['content'] != prompt) {
      out.add({'role': 'user', 'content': prompt});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<StudioController>();
    final palette = term.terminal.palette;
    final pi = term.pi;

    return Column(
      children: [
        _status(term, palette, pi),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'PI TERMINAL',
            accent: true,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            trailing: Text(
              _sessionId == null ? 'no session' : 'session ${_sessionId!.split('-').last}',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.dim,
              ),
            ),
            child: ListView.builder(
              controller: _scroll,
              itemCount: _lines.length,
              itemBuilder: (context, i) => _line(palette, _lines[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _composer(term, palette),
      ],
    );
  }

  Widget _status(StudioController studio, Palette palette, PiCore pi) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                studio.piOnline ? '●' : '○',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  color: studio.piOnline ? palette.ok : palette.warn,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                studio.piOnline ? 'PI READY' : 'PI NOT INSTALLED',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: studio.piOnline ? palette.bright : palette.warn,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${pi.installedVersion.isEmpty ? '—' : pi.installedVersion} · '
                  '${pi.models.length} models · '
                  '${pi.activeModel.isEmpty ? 'default' : pi.activeModel}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
              ),
            ],
          ),
          if (pi.updateAvailable) ...[
            const SizedBox(height: 4),
            Text(
              'update available: ${pi.installedVersion} → ${pi.latestVersion} '
              '(run `pi update`)',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.warn,
              ),
            ),
          ],
          if (studio.agentProvider == null) ...[
            const SizedBox(height: 4),
            Text(
              'no LLM key — prompts will fail until you add one in KEYS',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.err,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _composer(StudioController studio, Palette palette) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _running ? '◐' : '❯',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  color: palette.bright,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _input,
                  onSubmitted: (_) => _submit(studio),
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11,
                    color: palette.bright,
                  ),
                  cursorColor: palette.bright,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: _running ? 'working…' : 'pi …',
                    hintStyle: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 11,
                      color: palette.dim,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _running ? null : () => _submit(studio),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _running ? palette.dim : palette.bright,
                    ),
                  ),
                  child: Text(
                    _running ? '…' : 'RUN',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: _running ? palette.dim : palette.bright,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 20,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _commands.length,
              itemBuilder: (context, i) {
                final c = _commands[i];
                return GestureDetector(
                  onTap: _running
                      ? null
                      : () {
                          _input.text = c;
                          _input.selection = TextSelection.collapsed(
                            offset: c.length,
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: palette.line),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 8,
                          color: palette.dim,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(Palette palette, _Line l) {
    final color = switch (l.kind) {
      _Kind.cmd => palette.bright,
      _Kind.out => palette.mid,
      _Kind.sys => palette.dim,
      _Kind.err => palette.err,
      _Kind.agent => palette.ok,
    };
    final prefix = switch (l.kind) {
      _Kind.cmd => '❯ ',
      _Kind.err => '! ',
      _Kind.agent => 'π ',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText(
        '$prefix${l.text}',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 10.5,
          height: 1.45,
          color: color,
        ),
      ),
    );
  }
}

enum _Kind { cmd, out, sys, err, agent }

@immutable
class _Line {
  const _Line(this.text, this.kind);
  _Line.cmd(String t) : this('$t', _Kind.cmd);
  _Line.out(String t, {_Kind kind = _Kind.out, bool streaming = false})
      : this(t, kind);
  final String text;
  final _Kind kind;
}
