import 'package:flutter/material.dart';

/// Semantic colour role for a single rendered terminal line.
enum Tone { prompt, plain, dim, bright, ok, warn, err, heading, line, quote }

/// A single immutable line in the scrollback buffer.
///
/// Text may contain `*emphasis*` markers; everything between a pair of
/// asterisks is rendered in the palette's `bright` colour (or, when the base
/// tone is already bright, in `mid`). This is our tiny inline styling DSL.
@immutable
class TLine {
  const TLine(this.text, {this.tone = Tone.plain, this.glow = false});

  final String text;
  final Tone tone;

  /// Apply a soft phosphor bloom to this line (used sparingly).
  final bool glow;

  static const TLine blank = TLine('');
}

/// One parsed run of text, ready to be turned into a [TextSpan].
class TChunk {
  const TChunk(this.text, this.emphasised);
  final String text;
  final bool emphasised;
}

/// Split `*emphasis*` markup into chunks. An unmatched trailing `*` is kept
/// literally rather than swallowed, so users can type asterisks safely.
List<TChunk> parseMarkup(String text) {
  if (!text.contains('*')) {
    return [TChunk(text, false)];
  }
  final chunks = <TChunk>[];
  var buffer = StringBuffer();
  var open = false;
  for (final ch in text.split('')) {
    if (ch == '*') {
      if (buffer.isNotEmpty) {
        chunks.add(TChunk(buffer.toString(), open));
        buffer = StringBuffer();
      }
      open = !open;
    } else {
      buffer.write(ch);
    }
  }
  if (open) {
    // Unbalanced marker — restore it as plain text.
    chunks.add(TChunk('*', false));
  }
  if (buffer.isNotEmpty) {
    chunks.add(TChunk(buffer.toString(), false));
  }
  return chunks;
}

/// Left-align and pad to [width] (never truncates).
String pad(String s, int width) =>
    s.length >= width ? s : s + ' ' * (width - s.length);

/// Right-align and pad to [width].
String padLeft(String s, int width) =>
    s.length >= width ? s : ' ' * (width - s.length) + s;

/// Truncate with an ellipsis-free cut at [width] (terminal style).
String clip(String s, int width) {
  if (s.length <= width) return s;
  if (width <= 1) return s.substring(0, width);
  return '${s.substring(0, width - 1)}…';
}

/// Render a horizontal rule with an optional label, e.g.
/// `── SKY ──────────────────`
String ruleLine(String label, int width) {
  final safeWidth = width < 6 ? 6 : width;
  if (label.isEmpty) return '─' * safeWidth;
  final text = '─ $label ';
  final tail = safeWidth - text.length;
  return text + '─' * (tail > 0 ? tail : 0);
}

/// Format a signed coordinate like `+38.78°` / `-16.72°`.
String fmtDegrees(double value, {int decimals = 2}) {
  final sign = value < 0 ? '−' : '+';
  return '$sign${value.abs().toStringAsFixed(decimals)}°';
}

/// Format right ascension hours as `06h 45m`.
String fmtRa(double hours) {
  var h = hours % 24.0;
  if (h < 0) h += 24.0;
  final hh = h.floor();
  final mm = ((h - hh) * 60).floor();
  return '${hh.toString().padLeft(2, '0')}h ${mm.toString().padLeft(2, '0')}m';
}

/// Format declination as `+38° 47′`.
String fmtDec(double degrees) {
  final sign = degrees < 0 ? '−' : '+';
  final abs = degrees.abs();
  final d = abs.floor();
  final m = ((abs - d) * 60).round();
  return '$sign${d.toString().padLeft(2, '0')}° ${m.toString().padLeft(2, '0')}′';
}

/// Fixed-width magnitude string, e.g. `-1.46` / `+2.30`.
String fmtMag(double magnitude) {
  final s = magnitude.toStringAsFixed(2);
  return magnitude >= 0 ? '+$s' : '−${magnitude.abs().toStringAsFixed(2)}';
}

/// Human distance: `8.6 ly`, `2.6 kly`.
String fmtDistance(double ly) {
  if (ly <= 0) return '—';
  if (ly >= 1000) return '${(ly / 1000).toStringAsFixed(1)} kly';
  return '${ly.toStringAsFixed(ly < 100 ? 1 : 0)} ly';
}

/// A 12-cell meter used for altitude and magnitude bars.
String meter(
  double fraction, {
  int width = 12,
  String on = '█',
  String off = '·',
}) {
  final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
  final filled = (f * width).round();
  return on * filled + off * (width - filled);
}

/// UTC timestamp in ISO-ish terminal form: `2024-05-13 21:04:07Z`.
String fmtUtc(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// 24-hour local clock: `21:04:07`.
String fmtClock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Small helper: an ASCII progress bar is not used much but keeps the
/// boot sequence lively.
String bootBar(double fraction, int width) {
  const filledChar = '▓';
  const emptyChar = '░';
  final f = fraction.clamp(0.0, 1.0);
  final n = (f * width).round();
  return filledChar * n + emptyChar * (width - n);
}

/// Time-of-day greeting used by `whoami`.
String skyPhaseForHour(int hour) {
  if (hour < 4) return 'deep night';
  if (hour < 6) return 'astronomical dawn';
  if (hour < 8) return 'sunrise';
  if (hour < 17) return 'daylight';
  if (hour < 19) return 'sunset';
  if (hour < 21) return 'civil twilight';
  return 'night';
}

/// Choose a star tint for map rendering — spectral-class colouring.
Color spectralColor(String spectral) {
  final c = spectral.isEmpty ? 'G' : spectral[0].toUpperCase();
  switch (c) {
    case 'O':
      return const Color(0xFF9BB0FF);
    case 'B':
      return const Color(0xFFAABFFF);
    case 'A':
      return const Color(0xFFCAD7FF);
    case 'F':
      return const Color(0xFFF8F7FF);
    case 'G':
      return const Color(0xFFFFF4EA);
    case 'K':
      return const Color(0xFFFFDAB8);
    case 'M':
      return const Color(0xFFFFB56B);
    default:
      return const Color(0xFFCAD7FF);
  }
}
