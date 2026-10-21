import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/console_engine.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';
import '../widgets/terminal_line.dart';

/// The main console: scrollback buffer + prompt line + quick keys.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _blink;
  bool _cursorOn = true;
  int _lastLineCount = 0;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted) return;
      if (_focus.hasFocus) setState(() => _cursorOn = !_cursorOn);
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
      // The list is reversed, so "bottom" is offset 0.
      _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
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
            title: 'CONSOLE',
            accent: true,
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
            trailing: _statusChips(term, palette),
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
                    // Reversed list: newest line sits at index 0 of the
                    // viewport bottom, so read the buffer backwards.
                    final line = term.lines[term.lines.length - 1 - i];
                    // Multi-line wrapped notes are pre-split by the engine,
                    // but a `\n` can still arrive from _wrap().
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
        const SizedBox(height: 8),
        _promptBar(term, palette, fontSize),
        const SizedBox(height: 8),
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

  Widget _statusChips(TerminalController term, Palette palette) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip('${term.visibleCount} up', palette, color: palette.ok),
        const SizedBox(width: 6),
        _chip(
          term.trackingLive && term.timeOffsetHours == 0 ? 'LIVE' : 'OFFSET',
          palette,
          color: term.trackingLive && term.timeOffsetHours == 0
              ? palette.mid
              : palette.warn,
        ),
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
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8,
          height: 1.25,
          letterSpacing: 1.0,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _promptBar(TerminalController term, Palette palette, double fontSize) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Block cursor, drawn behind the text at the caret position.
                // Only shown when the field is empty or has focus + is on.
                if (_focus.hasFocus && _cursorOn && _text.text.isEmpty)
                  Container(
                    width: fontSize * 0.58,
                    height: fontSize * 1.15,
                    color: palette.bright.withValues(alpha: 0.8),
                  ),
                TextField(
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
                  onSubmitted: (_) => _submit(term),
                  onChanged: (v) => term.setInput(v),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '',
                  ),
                ),
              ],
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
      onTap: () {
        term.historyStep(dir);
        _text.text = term.input;
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
        _focus.requestFocus();
      },
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
      onTap: () => _submit(term),
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

  void _submit(TerminalController term) {
    final value = _text.text;
    _text.clear();
    if (value.trim().isEmpty) {
      term.setInput('');
      term.submit();
      return;
    }
    // Shell builtins first: a real working directory beats a fixed grammar.
    final studio = context.read<StudioController>();
    final shell = studio.shellExec(value);
    if (shell != null) {
      term.print('❯ $value', tone: Tone.heading);
      for (final l in shell.split('\n')) {
        if (l.isNotEmpty) term.print(l);
      }
      if (shell.isNotEmpty) studio.appLog.info(shell, scope: 'shell');
      _scrollToBottom();
      _focus.requestFocus();
      return;
    }
    term.setInput(value);
    term.submit();
    _scrollToBottom();
    _focus.requestFocus();
  }

  Widget _quickKeys(TerminalController term, Palette palette) {
    const keys = <String>['help', 'sky', 'top', 'moon', 'map', 'notes'];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final k = keys[i];
          return InkWell(
            onTap: () {
              term.runCommand(k);
              _scrollToBottom();
              _focus.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: palette.line),
                color: palette.panel.withValues(alpha: 0.6),
              ),
              alignment: Alignment.center,
              child: Text(
                k,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  letterSpacing: 0.6,
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
