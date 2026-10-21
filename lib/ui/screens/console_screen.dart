import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/console_engine.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';
import '../widgets/term_keys.dart';
import '../widgets/terminal_line.dart';

/// The main console: scrollback buffer + prompt line + cursor controller.
///
/// This is a shell first and a sky console second. Anything that is a real
/// filesystem command runs against the VFS; anything else falls through to the
/// terminal's own grammar. Chips only advertise commands that actually work.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final TermCursor _cursor;
  Timer? _blink;
  bool _cursorOn = true;
  int _lastLineCount = 0;
  List<String> _suggest = const [];

  /// Every command the console actually understands, shell and builtin.
  static const List<String> _index = [
    'help', 'ls', 'cd', 'pwd', 'cat', 'echo', 'mkdir', 'touch', 'rm', 'df',
    'clear', 'history', 'pi', 'keys', 'fx', 'agent', 'ask', 'fleet',
    'note', 'notes', 'sky', 'top', 'star', 'moon', 'map', 'theme', 'whoami',
    'status', 'about', 'banner', 'login',
  ];

  @override
  void initState() {
    super.initState();
    _cursor = TermCursor(
      _text,
      onSubmit: _send,
      onCancel: _cancel,
      onComplete: (v) => _complete(v),
    );
    _focus.requestFocus();
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted) return;
      if (_focus.hasFocus) {
        setState(() => _cursorOn = !_cursorOn);
      }
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final studio = context.watch<StudioController>();
    final palette = term.palette;
    final fontSize = _consoleFontSize(context);

    if (term.lines.length != _lastLineCount) {
      _lastLineCount = term.lines.length;
      _scrollToBottom();
    }

    return Column(
      children: [
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'SHELL',
            accent: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
            trailing: _statusChips(term, studio, palette),
            child: GestureDetector(
              onTap: () => _focus.requestFocus(),
              behavior: HitTestBehavior.opaque,
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                thickness: 3,
                child: ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: term.lines.length,
                  itemBuilder: (context, i) {
                    final line = term.lines[term.lines.length - 1 - i];
                    if (line.text.contains('\n')) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final part in line.text.split('\n'))
                            TerminalLine(
                              line: TLine(part, tone: line.tone),
                              palette: palette,
                              fontSize: fontSize,
                            ),
                        ],
                      );
                    }
                    return TerminalLine(
                      line: line,
                      palette: palette,
                      fontSize: fontSize,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_suggest.isNotEmpty)
          SuggestPopup(
            palette: palette,
            items: _suggest,
            onPick: (cmd) {
              _cursor.setText(cmd);
              setState(() => _suggest = const []);
              _focus.requestFocus();
            },
          ),
        _promptBar(term, palette, fontSize),
        const SizedBox(height: 5),
        TermKeyBar(
          palette: palette,
          cursor: _cursor,
          compact: true,
          extra: [
            TermKey('↑', () => _history(term, -1), hint: 'history'),
            TermKey('│', () => _cursor.insert(' | '), hint: 'pipe'),
            TermKey('↵', _send, accent: palette.ok, hint: 'run'),
          ],
        ),
        const SizedBox(height: 5),
        _quickKeys(term, palette),
      ],
    );
  }

  double _consoleFontSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 400) return 11.5;
    if (width < 700) return 12.5;
    return 13.5;
  }

  Widget _statusChips(
    TerminalController term,
    StudioController studio,
    Palette palette,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(studio.fs.prompt, palette, color: palette.ok),
        const SizedBox(width: 5),
        _chip(
          studio.piOnline ? 'pi ${studio.pi.installedVersion}' : 'pi absent',
          palette,
          color: studio.piOnline ? palette.mid : palette.warn,
        ),
        const SizedBox(width: 5),
        if (studio.agentProvider == null)
          _chip('no key', palette, color: palette.err)
        else
          _chip(studio.agentProvider!.id, palette, color: palette.mid),
      ],
    );
  }

  Widget _chip(String label, Palette palette, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.07),
      ),
      constraints: const BoxConstraints(maxWidth: 110),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8,
          height: 1.25,
          letterSpacing: 0.8,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _promptBar(TerminalController term, Palette palette, double fontSize) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '❯',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: fontSize + 2,
              fontWeight: FontWeight.w700,
              color: palette.bright,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              cursorColor: palette.bright,
              cursorWidth: 6,
              cursorHeight: fontSize * 1.15,
              style: _inputStyle(palette, fontSize),
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              onTap: () => _focus.requestFocus(),
              onSubmitted: (_) => _send(),
              onChanged: (v) {
                term.setInput(v);
                _updateSuggestions(v);
              },
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'type a command, or `help`',
                hintStyle: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: fontSize - 0.5,
                  color: palette.dim.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          if (_cursorOn && _focus.hasFocus && _text.text.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: fontSize * 0.58,
                height: fontSize * 1.15,
                color: palette.bright.withValues(alpha: 0.75),
              ),
            ),
          _historyArrows(term, palette, fontSize),
          const SizedBox(width: 6),
          _sendButton(term, palette, fontSize),
        ],
      ),
    );
  }

  TextStyle _inputStyle(Palette palette, double fontSize) => TextStyle(
    fontFamily: 'Mono',
    fontSize: fontSize,
    height: 1.30,
    color: palette.bright,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  Widget _historyArrows(
    TerminalController term,
    Palette palette,
    double fontSize,
  ) {
    Widget button(String glyph, int dir) => InkWell(
      onTap: () => _history(term, dir),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          glyph,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: fontSize,
            color: palette.dim,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [button('▲', -1), button('▼', 1)],
    );
  }

  Widget _sendButton(
    TerminalController term,
    Palette palette,
    double fontSize,
  ) {
    return InkWell(
      onTap: _send,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: palette.mid.withValues(alpha: 0.6)),
          color: palette.mid.withValues(alpha: 0.10),
        ),
        child: Text(
          'RUN',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: fontSize - 1.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: palette.bright,
          ),
        ),
      ),
    );
  }

  // ── behaviour ────────────────────────────────────────────────────────

  void _history(TerminalController term, int dir) {
    term.historyStep(dir);
    _cursor.setText(term.input);
    _focus.requestFocus();
  }

  /// Prefix-match against the command index, shell builtins included.
  void _updateSuggestions(String value) {
    final v = value.trim();
    if (v.isEmpty || v.contains(' ')) {
      if (_suggest.isNotEmpty) setState(() => _suggest = const []);
      return;
    }
    final hits = _index.where((c) => c.startsWith(v) && c != v).toList();
    if (hits.length == _suggest.length &&
        hits.every(_suggest.contains)) {
      return;
    }
    setState(() => _suggest = hits);
  }

  String? _complete(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    final hits = _index.where((c) => c.startsWith(v)).toList();
    if (hits.isEmpty) return null;
    if (hits.length == 1) return '${hits.first} ';
    // Longest common prefix.
    var prefix = hits.first;
    for (final c in hits.skip(1)) {
      var i = 0;
      while (i < prefix.length && i < c.length && prefix[i] == c[i]) {
        i++;
      }
      prefix = prefix.substring(0, i);
    }
    return prefix == value ? null : prefix;
  }

  void _cancel() {
    _text.clear();
    setState(() => _suggest = const []);
    _focus.requestFocus();
  }

  void _send() {
    final value = _text.text;
    _text.clear();
    setState(() => _suggest = const []);
    if (value.trim().isEmpty) {
      context.read<TerminalController>().setInput('');
      context.read<TerminalController>().submit();
      return;
    }

    final term = context.read<TerminalController>();
    final studio = context.read<StudioController>();

    // 1. Shell builtins run against the VFS.
    final shell = studio.shellExec(value);
    if (shell != null) {
      term.print('❯ $value', tone: Tone.heading);
      if (shell.isEmpty) {
        // `cd` and friends legitimately produce nothing.
      } else {
        for (final l in shell.split('\n')) {
          if (l.isNotEmpty) term.print(l);
        }
      }
      studio.appLog.info(
        shell.isEmpty ? value : shell.split('\n').first,
        scope: 'shell',
      );
      _scrollToBottom();
      _focus.requestFocus();
      return;
    }

    // 2. Everything else goes to the terminal's own grammar.
    term.setInput(value);
    term.submit();
    _scrollToBottom();
    _focus.requestFocus();
  }

  Widget _quickKeys(TerminalController term, Palette palette) {
    // Only commands that demonstrably work — the old chips advertised a
    // sky-only vocabulary that made the console feel like a toy.
    const keys = <String>['ls', 'help', 'pi status', 'keys', 'fx', 'agent'];
    return SizedBox(
      height: 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, i) {
          final k = keys[i];
          return InkWell(
            onTap: () {
              _cursor.setText(k);
              _focus.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: palette.line),
                color: palette.panel.withValues(alpha: 0.6),
              ),
              alignment: Alignment.center,
              child: Text(
                k,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9.5,
                  letterSpacing: 0.5,
                  color: palette.mid,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
