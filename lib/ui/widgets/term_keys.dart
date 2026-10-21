import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';

/// A hardware-keyboard-style cursor controller for a [TextField].
///
/// This is the piece that makes the terminal feel like Termux rather than a
/// chat box. On a phone there are no arrow keys, so without this you can only
/// append and delete at the end of the line. [TermCursor] exposes the editing
/// primitives a real terminal has — motion, selection, kill-line, completion —
/// and wraps them in an on-screen bar.
///
/// Pass the same instance to both a [TextField] and a [TermKeyBar].
class TermCursor {
  TermCursor(this.controller, {this.onSubmit, this.onCancel, this.onComplete});

  final TextEditingController controller;

  /// Fired by the ↵ key on the bar.
  final VoidCallback? onSubmit;

  /// Fired by ^C — abandon the current line or turn.
  final VoidCallback? onCancel;

  /// Fired by TAB. Returns the replacement text (or null to leave it alone).
  final String? Function(String value)? onComplete;

  TextEditingValue get _v => controller.value;
  String get text => _v.text;
  int get _len => _v.text.length;

  int get selectionStart => _v.selection.isValid ? _v.selection.start : _len;
  int get selectionEnd => _v.selection.isValid ? _v.selection.end : _len;
  bool get hasSelection => _v.selection.isValid && !_v.selection.isCollapsed;

  void _set(String text, int caret, {int? selEnd}) {
    final safe = caret.clamp(0, text.length);
    final end = (selEnd ?? caret).clamp(0, text.length);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selEnd == null ? safe : end,
        extentOffset: safe,
      ),
    );
  }

  void _caret(int pos) {
    final p = pos.clamp(0, _len);
    controller.selection = TextSelection.collapsed(offset: p);
  }

  // ── motion ───────────────────────────────────────────────────────────

  void left() {
    if (hasSelection) {
      _caret(selectionStart);
      return;
    }
    _caret(selectionStart - 1);
  }

  void right() {
    if (hasSelection) {
      _caret(selectionEnd);
      return;
    }
    _caret(selectionEnd + 1);
  }

  /// Move left by one shell word (skips trailing spaces).
  void wordLeft() {
    final t = _v.text;
    var i = selectionStart - 1;
    while (i > 0 && t[i] == ' ') {
      i--;
    }
    while (i > 0 && t[i - 1] != ' ') {
      i--;
    }
    _caret(i);
  }

  void wordRight() {
    final t = _v.text;
    var i = selectionEnd;
    while (i < t.length && t[i] != ' ') {
      i++;
    }
    while (i < t.length && t[i] == ' ') {
      i++;
    }
    _caret(i);
  }

  void home() => _caret(0);
  void end() => _caret(_len);

  void selectAll() {
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _len);
  }

  // ── editing ──────────────────────────────────────────────────────────

  void backspace() {
    if (hasSelection) {
      _set(
        _v.text.replaceRange(selectionStart, selectionEnd, ''),
        selectionStart,
      );
      return;
    }
    final i = selectionStart;
    if (i <= 0) return;
    _set(_v.text.replaceRange(i - 1, i, ''), i - 1);
  }

  void delete() {
    if (hasSelection) {
      _set(
        _v.text.replaceRange(selectionStart, selectionEnd, ''),
        selectionStart,
      );
      return;
    }
    final i = selectionStart;
    if (i >= _len) return;
    _set(_v.text.replaceRange(i, i + 1, ''), i);
  }

  /// Ctrl-U: kill from the caret back to the start of the line.
  void killToStart() {
    final i = selectionStart;
    if (i <= 0) return;
    _set(_v.text.substring(i), 0);
  }

  /// Ctrl-K: kill from the caret to the end of the line.
  void killToEnd() => _set(_v.text.substring(0, selectionStart), selectionStart);

  /// Ctrl-W: kill the word before the caret.
  void killWord() {
    final t = _v.text;
    final i = selectionStart;
    if (i <= 0) return;
    var j = i - 1;
    while (j > 0 && t[j] == ' ') {
      j--;
    }
    while (j > 0 && t[j - 1] != ' ') {
      j--;
    }
    _set(t.replaceRange(j, i, ''), j);
  }

  void insert(String s) {
    if (hasSelection) {
      _set(
        _v.text.replaceRange(selectionStart, selectionEnd, s),
        selectionStart + s.length,
      );
      return;
    }
    final i = selectionStart;
    _set(
      _v.text.replaceRange(i, i, s),
      i + s.length,
    );
  }

  /// Accept the whole buffer from a history recall or a chip tap.
  void setText(String s) {
    _set(s, s.length);
  }

  // ── terminal actions ─────────────────────────────────────────────────

  void tab() {
    final cb = onComplete;
    if (cb == null) return;
    final next = cb(_v.text);
    if (next == null || next == _v.text) return;
    // Keep everything after the cursor so completing mid-line is not
    // destructive.
    final caret = selectionStart;
    final rest = _v.text.substring(caret);
    setText(next + rest);
  }

  void submit() => onSubmit?.call();

  void cancel() => onCancel?.call();
}

/// The on-screen key bar. Sits under the composer in both CONSOLE and PI.
///
/// Deliberately laid out like a hardware bottom row: motion on the left,
/// destructive keys in the middle, modifiers on the right, where a thumb
/// reaches first.
class TermKeyBar extends StatelessWidget {
  const TermKeyBar({
    super.key,
    required this.palette,
    required this.cursor,
    this.compact = false,
    this.extra = const [],
  });

  final Palette palette;
  final TermCursor cursor;

  /// Tighter metrics for short screens.
  final bool compact;

  /// Page-specific keys appended on the right (e.g. `/` `/status`).
  final List<TermKey> extra;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 27.0 : 30.0;
    final keys = <TermKey>[
      TermKey('←', () => cursor.left(), hint: 'left'),
      TermKey('→', () => cursor.right(), hint: 'right'),
      TermKey('⇤', () => cursor.home(), hint: 'home'),
      TermKey('⇥', () => cursor.end(), hint: 'end'),
      TermKey('⌫', cursor.backspace, hint: 'backspace'),
      TermKey('⇟', cursor.killToEnd, hint: 'kill to end'),
      TermKey('TAB', cursor.tab, accent: palette.ok, hint: 'complete'),
      TermKey('^C', cursor.cancel, accent: palette.err, hint: 'cancel'),
      ...extra,
    ];

    // A scrolling row looked tidy but hid the right-most keys — the modifiers
    // and the page-specific actions — with no affordance that they existed.
    // A wrap keeps every key reachable and reflows to two rows on narrow
    // phones instead of clipping.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the key width until the whole bar fits on one row, so the
        // common case never wraps and the layout stays a hardware row.
        final n = keys.length;
        final gap = 3.0;
        final avail = constraints.maxWidth - gap * (n - 1);
        final per = (avail / n).clamp(24.0, 44.0);
        final fits = per >= 26;
        return Wrap(
          spacing: gap,
          runSpacing: 3,
          children: [
            for (final k in keys)
              _key(palette, k, h, fits ? per : (compact ? 30.0 : 34.0)),
          ],
        );
      },
    );
  }

  Widget _key(Palette palette, TermKey k, double height, double width) {
    final tint = k.accent ?? palette.mid;
    return Tooltip(
      message: k.hint,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          k.onTap();
        },
        onLongPress: k.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                k.onLongPress!();
              },
        child: Container(
          height: height,
          width: width,
          constraints: BoxConstraints(minWidth: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.panel.withValues(alpha: 0.85),
            border: Border.all(color: tint.withValues(alpha: 0.55)),
          ),
          child: Text(
            k.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: k.label.length > 1 ? 9.5 : 11.5,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class TermKey {
  const TermKey(
    this.label,
    this.onTap, {
    this.hint = '',
    this.accent,
    this.onLongPress,
  });
  final String label;
  final VoidCallback onTap;
  final String hint;
  final Color? accent;
  final VoidCallback? onLongPress;
}

/// A popup list of completions that floats above the composer.
///
/// Tapping a suggestion runs [onPick] with the plain command text (before the
/// two-space summary separator).
class SuggestPopup extends StatelessWidget {
  const SuggestPopup({
    super.key,
    required this.palette,
    required this.items,
    required this.onPick,
    this.max = 6,
  });

  final Palette palette;
  final List<String> items;
  final ValueChanged<String> onPick;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(max).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in shown)
            InkWell(
              onTap: () => onPick(item.split('  ').first.trim()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9.5,
                    color: palette.mid,
                  ),
                ),
              ),
            ),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
              child: Text(
                '+${items.length - shown.length} more…',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
