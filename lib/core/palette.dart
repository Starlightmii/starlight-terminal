import 'package:flutter/material.dart';

/// The four CRT phosphor palettes the terminal can boot into.
enum TerminalPalette { phosphor, amber, ice, nebula }

class Palette {
  const Palette({
    required this.id,
    required this.label,
    required this.description,
    required this.bg,
    required this.panel,
    required this.line,
    required this.dim,
    required this.mid,
    required this.bright,
    required this.ok,
    required this.warn,
    required this.err,
  });

  final TerminalPalette id;
  final String label;
  final String description;

  /// Deepest background behind everything.
  final Color bg;

  /// Slightly lifted surface used for panels.
  final Color panel;

  /// Hairline / border colour.
  final Color line;

  /// Recedes into the background: comments, metadata.
  final Color dim;

  /// Body text.
  final Color mid;

  /// Highlight, headings, glowing accents.
  final Color bright;

  final Color ok;
  final Color warn;
  final Color err;

  static const Palette phosphor = Palette(
    id: TerminalPalette.phosphor,
    label: 'PHOSPHOR',
    description: 'P1 green phosphor — the classic observatory tube.',
    bg: Color(0xFF020705),
    panel: Color(0xFF06110B),
    line: Color(0xFF0E3B27),
    dim: Color(0xFF1F7A50),
    mid: Color(0xFF4FD79A),
    bright: Color(0xFF7CFFC4),
    ok: Color(0xFF7CFFC4),
    warn: Color(0xFFFFD166),
    err: Color(0xFFFF6B6B),
  );

  static const Palette amber = Palette(
    id: TerminalPalette.amber,
    label: 'AMBER',
    description: 'P3 amber — warm, low-fatigue, late-shift friendly.',
    bg: Color(0xFF0A0501),
    panel: Color(0xFF150C04),
    line: Color(0xFF40280B),
    dim: Color(0xFF8A5C1B),
    mid: Color(0xFFE0A046),
    bright: Color(0xFFFFCB6B),
    ok: Color(0xFFB7E07A),
    warn: Color(0xFFFFD166),
    err: Color(0xFFFF7B5C),
  );

  static const Palette ice = Palette(
    id: TerminalPalette.ice,
    label: 'ICE',
    description: 'Cyan phosphor — cold aperture, deep field.',
    bg: Color(0xFF02070B),
    panel: Color(0xFF051018),
    line: Color(0xFF0E3648),
    dim: Color(0xFF1C6C8A),
    mid: Color(0xFF5FC6E8),
    bright: Color(0xFF9DEBFF),
    ok: Color(0xFF7CFFD6),
    warn: Color(0xFFFFD166),
    err: Color(0xFFFF6B9D),
  );

  static const Palette nebula = Palette(
    id: TerminalPalette.nebula,
    label: 'NEBULA',
    description: 'Violet phosphor — hydrogen-alpha, moody.',
    bg: Color(0xFF06040D),
    panel: Color(0xFF0C0817),
    line: Color(0xFF2A2050),
    dim: Color(0xFF5D4BA0),
    mid: Color(0xFFA98BE8),
    bright: Color(0xFFD6BCFF),
    ok: Color(0xFF8FFFE0),
    warn: Color(0xFFFFC978),
    err: Color(0xFFFF79A8),
  );

  static const List<Palette> all = [phosphor, amber, ice, nebula];

  static Palette byName(String name) {
    final needle = name.trim().toLowerCase();
    for (final p in all) {
      if (p.label.toLowerCase() == needle) return p;
    }
    return phosphor;
  }

  Palette next() {
    final i = all.indexWhere((p) => p.id == id);
    return all[(i + 1) % all.length];
  }
}
