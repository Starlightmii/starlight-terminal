import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/pi_session.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';
import '../widgets/term_keys.dart';

/// The pi workbench: a real terminal session running the pi agent.
///
/// There is deliberately no connect/reconnect/sync-keys control here. Earlier
/// builds drove a loopback HTTP broker, which cannot exist on a phone; that
/// whole layer is gone. This screen is a shell: you type, pi answers, and the
/// transcript *is* the session. Slash commands mirror pi.dev's own reference.
class PiScreen extends StatefulWidget {
  const PiScreen({super.key});

  @override
  State<PiScreen> createState() => _PiScreenState();
}

class _PiScreenState extends State<PiScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  late final TermCursor _cursor;
  int _lastLineCount = 0;

  @override
  void initState() {
    super.initState();
    _cursor = TermCursor(
      _input,
      onSubmit: _send,
      onCancel: _cancel,
      onComplete: (v) => context.read<StudioController>().piSession.complete(v),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final studio = context.read<StudioController>();
    final raw = _input.text;
    if (raw.trim().isEmpty) return;
    _input.clear();
    studio.piSession.submit(raw);
    _snap();
    _focus.requestFocus();
  }

  void _cancel() {
    final studio = context.read<StudioController>();
    if (studio.piSession.running) {
      studio.piSession.cancel();
      return;
    }
    _input.clear();
  }

  void _snap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final session = studio.piSession;
    final palette = studio.terminal.palette;

    if (session.lines.length != _lastLineCount) {
      _lastLineCount = session.lines.length;
      _snap();
    }

    return Column(
      children: [
        _statusBar(studio, palette, session),
        const SizedBox(height: 6),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'PI',
            accent: true,
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session.running) ...[
                  Text(
                    '◐ streaming',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 8.5,
                      color: palette.ok,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  session.sessionId == null
                      ? 'no session'
                      : 'session ${session.sessionId!.split('-').last}',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: () => _focus.requestFocus(),
              behavior: HitTestBehavior.opaque,
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                thickness: 3,
                child: ListView.builder(
                  controller: _scroll,
                  physics: const ClampingScrollPhysics(),
                  itemCount: session.lines.length,
                  itemBuilder: (context, i) =>
                      _line(palette, session.lines[i]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _composer(studio, palette, session),
        const SizedBox(height: 5),
        TermKeyBar(
          palette: palette,
          cursor: _cursor,
          extra: [
            TermKey('/', () {
              _cursor.insert('/');
              _refreshSuggestions(studio);
            }, accent: palette.warn, hint: 'slash command'),
            TermKey('!', () {
              _cursor.insert('!');
            }, hint: 'shell'),
            TermKey('@', () {
              _cursor.insert('@');
            }, hint: 'attach file'),
            TermKey('↑', () {
              _recall(studio, -1);
            }, hint: 'history'),
            TermKey('↵', () {
              _send();
            }, accent: palette.ok, hint: 'send'),
          ],
        ),
      ],
    );
  }

  void _refreshSuggestions(StudioController studio) {
    studio.piSession.onInputChanged(_input.text);
    _focus.requestFocus();
  }

  void _recall(StudioController studio, int dir) {
    final hist = studio.piSession.history;
    if (hist.isEmpty) return;
    final cur = _input.text;
    var idx = hist.lastIndexOf(cur);
    if (idx < 0) {
      idx = hist.length - 1;
    } else {
      idx = (idx + dir).clamp(0, hist.length - 1);
    }
    _cursor.setText(hist[idx]);
  }

  /// Status strip: one line, dense, no boxes inside boxes.
  Widget _statusBar(
    StudioController studio,
    Palette palette,
    PiSession session,
  ) {
    final pi = studio.pi;
    final provider = studio.agentProvider;
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                studio.piOnline ? '●' : '○',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11,
                  color: studio.piOnline ? palette.ok : palette.warn,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                studio.piOnline ? 'PI READY' : 'PI ABSENT',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9.5,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                  color: studio.piOnline ? palette.bright : palette.warn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${pi.installedVersion.isEmpty ? '—' : pi.installedVersion} · '
                  '${pi.activeModel.isEmpty ? 'default model' : pi.activeModel} · '
                  '${session.thinking.label}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
              ),
              // Thinking level is a tap target, not a menu: the common case is
              // "one notch more" or "one notch less".
              GestureDetector(
                onTap: () => session.cycleThinking(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.line),
                  ),
                  child: Text(
                    'think:${session.thinking.label}',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 8,
                      color: palette.mid,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (provider == null || pi.updateAvailable) ...[
            const SizedBox(height: 3),
            Text(
              provider == null
                  ? 'no LLM key — add one in KEYS; pi runs on your own key'
                  : 'update available ${pi.installedVersion} → ${pi.latestVersion} — run /update',
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

  Widget _composer(
    StudioController studio,
    Palette palette,
    PiSession session,
  ) {
    final running = session.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.suggestions.isNotEmpty)
          SuggestPopup(
            palette: palette,
            items: session.suggestions,
            onPick: (cmd) {
              _cursor.setText(cmd);
              studio.piSession.onInputChanged(cmd);
              _focus.requestFocus();
            },
          ),
        TermPanel(
          palette: palette,
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Row(
            children: [
              Text(
                running ? '◐' : 'π',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: running ? palette.ok : palette.bright,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  onSubmitted: (_) => _send(),
                  onChanged: (v) {
                    studio.piSession.onInputChanged(v);
                  },
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11.5,
                    height: 1.35,
                    color: palette.bright,
                  ),
                  cursorColor: palette.bright,
                  cursorWidth: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: running ? 'working…' : 'prompt, /command, !shell, @file',
                    hintStyle: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 10.5,
                      color: palette.dim,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: running
                    ? () {
                        studio.piSession.cancel();
                      }
                    : _send,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: running ? palette.err : palette.bright,
                    ),
                    color: running
                        ? palette.err.withValues(alpha: 0.10)
                        : palette.bright.withValues(alpha: 0.06),
                  ),
                  child: Text(
                    running ? 'STOP' : 'RUN',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: running ? palette.err : palette.bright,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── transcript rendering ─────────────────────────────────────────────

  Widget _line(Palette palette, PiLine l) {
    if (l.text.isEmpty) return SizedBox(height: 6);

    final (color, prefix) = switch (l.kind) {
      PiLineKind.prompt => (palette.bright, '❯ '),
      PiLineKind.reply => (palette.mid, ''),
      PiLineKind.thinking => (palette.dim, '~ '),
      PiLineKind.tool => (palette.ok, '  '),
      PiLineKind.sys => (palette.dim, ''),
      PiLineKind.err => (palette.err, '! '),
      PiLineKind.cmd => (palette.bright, ''),
      PiLineKind.info => (palette.warn, ''),
    };

    final body = '$prefix${l.text}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: l.kind == PiLineKind.thinking ? 2 : 6,
        left: l.kind == PiLineKind.tool ? 10 : 0,
      ),
      child: SelectableText(
        body,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 10.5,
          height: 1.42,
          color: color,
          fontStyle: l.kind == PiLineKind.thinking
              ? FontStyle.italic
              : FontStyle.normal,
        ),
      ),
    );
  }
}
