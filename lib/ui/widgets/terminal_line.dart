import 'package:flutter/material.dart';

import '../../core/console_engine.dart';
import '../../core/palette.dart';

/// Renders a single [TLine] with palette-resolved colour and optional bloom.
///
/// Uses a fixed line height so the scrollback aligns with the input row and
/// the column maths in the command tables stays honest.
class TerminalLine extends StatelessWidget {
  const TerminalLine({
    super.key,
    required this.line,
    required this.palette,
    required this.fontSize,
  });

  final TLine line;
  final Palette palette;
  final double fontSize;

  Color _baseColor() {
    switch (line.tone) {
      case Tone.prompt:
        return palette.bright;
      case Tone.plain:
        return palette.mid;
      case Tone.dim:
        return palette.dim;
      case Tone.bright:
        return palette.bright;
      case Tone.ok:
        return palette.ok;
      case Tone.warn:
        return palette.warn;
      case Tone.err:
        return palette.err;
      case Tone.heading:
        return palette.bright;
      case Tone.line:
        return palette.line;
      case Tone.quote:
        return palette.mid;
    }
  }

  Color _emphasisColor() {
    if (line.tone == Tone.bright || line.tone == Tone.heading) {
      return palette.mid;
    }
    return palette.bright;
  }

  TextStyle _style(Color color, {bool bold = false, bool italic = false}) {
    return TextStyle(
      fontFamily: 'Mono',
      fontSize: fontSize,
      height: 1.30,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: 0.1,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (line.text.isEmpty) {
      return SizedBox(height: fontSize * 1.30);
    }

    final chunks = parseMarkup(line.text);
    final baseColor = _baseColor();
    final bold = line.tone == Tone.heading || line.tone == Tone.prompt;
    final italic = line.tone == Tone.quote;

    final spans = <TextSpan>[
      for (final c in chunks)
        TextSpan(
          text: c.text,
          style: _style(
            c.emphasised ? _emphasisColor() : baseColor,
            bold: bold || c.emphasised,
            italic: italic,
          ),
        ),
    ];

    final text = Text.rich(
      TextSpan(children: spans),
      softWrap: true,
      textWidthBasis: TextWidthBasis.parent,
    );

    if (!line.glow) return text;

    return Text.rich(
      TextSpan(children: spans),
      softWrap: true,
      textWidthBasis: TextWidthBasis.parent,
      strutStyle: StrutStyle(
        fontFamily: 'Mono',
        fontSize: fontSize,
        height: 1.30,
      ),
      style: TextStyle(
        shadows: [
          Shadow(color: palette.bright.withValues(alpha: 0.55), blurRadius: 8),
          Shadow(color: palette.bright.withValues(alpha: 0.25), blurRadius: 16),
        ],
      ),
    );
  }
}
