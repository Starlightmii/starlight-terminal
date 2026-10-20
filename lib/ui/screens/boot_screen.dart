import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/console_engine.dart';
import '../../core/palette.dart';
import '../../state/terminal_controller.dart';

/// Pre-session boot screen: tube warm-up, banner, progress.
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in bannerLines)
                      Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 9,
                          height: 1.05,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w700,
                          color: palette.bright,
                          shadows: [
                            Shadow(
                              color: palette.bright.withValues(alpha: 0.7),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'sky console · local catalogue · no network',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: palette.dim,
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text(
                    bootBar(term.bootProgress, 28),
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 12,
                      letterSpacing: 1,
                      color: palette.mid,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(term.bootProgress * 100).round().toString().padLeft(3)}%',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 11,
                      color: palette.mid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '  ${term.bootMessage}',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11.5,
                  color: palette.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Global status bar pinned to the top of the shell.
class TopStatusBar extends StatelessWidget {
  const TopStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;
    final obs = term.observationTime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Text(
            'ST★RLIGHT',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: palette.bright,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 12, color: palette.line),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              clip(term.siteName, 18),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                letterSpacing: 0.5,
                color: palette.dim,
              ),
            ),
          ),
          const Spacer(),
          _dot(palette, term.trackingLive && term.timeOffsetHours == 0),
          const SizedBox(width: 6),
          Text(
            fmtClock(obs),
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.mid,
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: term.cyclePalette,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: palette.line),
              ),
              child: Text(
                term.palette.label,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: palette.mid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Palette palette, bool live) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? palette.ok : palette.warn,
        boxShadow: [
          BoxShadow(
            color: (live ? palette.ok : palette.warn).withValues(alpha: 0.7),
            blurRadius: 5,
          ),
        ],
      ),
    );
  }
}

/// Bottom navigation, terminal-style: bracketed tabs rather than icons.
class TermNavBar extends StatelessWidget {
  const TermNavBar({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const List<({String label, String glyph})> tabs = [
    (label: 'CONSOLE', glyph: '❯'),
    (label: 'MAP', glyph: '◎'),
    (label: 'STARS', glyph: '★'),
    (label: 'AGENTS', glyph: '◈'),
    (label: 'PI', glyph: '⌸'),
    (label: 'KEYS', glyph: '⚿'),
    (label: 'FX', glyph: '≋'),
    (label: 'LOG', glyph: '≡'),
    (label: 'SYSTEM', glyph: '⚙'),
  ];

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.85),
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: EdgeInsets.only(
        top: 7,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(i),
                splashColor: palette.mid.withValues(alpha: 0.12),
                highlightColor: palette.mid.withValues(alpha: 0.06),
                child: _tab(i, tabs[i], palette, i == index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(
    int i,
    ({String label, String glyph}) tab,
    Palette palette,
    bool active,
  ) {
    final color = active ? palette.bright : palette.mid.withValues(alpha: 0.75);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.glyph,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 12,
                height: 1.0,
                color: color,
                shadows: active
                    ? [
                        Shadow(
                          color: palette.bright.withValues(alpha: 0.8),
                          blurRadius: 9,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                height: 1.0,
                letterSpacing: 0.4,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: color,
                decoration: active ? TextDecoration.underline : null,
                decorationColor: palette.bright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings / about screen.
class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      children: [
        _section(palette, 'DISPLAY', [
          _row(palette, 'palette', _paletteSwatches(term, palette)),
          _row(
            palette,
            'scanlines',
            _switch(
              palette,
              term.crtEnabled,
              term.toggleCrt,
              onLabel: 'ON',
              offLabel: 'OFF',
            ),
          ),
        ]),
        _section(palette, 'OBSERVING SITE', [
          _row(
            palette,
            'name',
            Text(
              term.siteName,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
          _row(
            palette,
            'latitude',
            Text(
              term.latitude.toStringAsFixed(4),
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
          _row(
            palette,
            'longitude',
            Text(
              term.longitude.toStringAsFixed(4),
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
          _row(
            palette,
            'presets',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _preset(term, palette, 'Greenwich', 51.4779, -0.0015),
                _preset(term, palette, 'Mauna Kea', 19.8207, -155.4681),
                _preset(term, palette, 'Atacama', -24.6272, -70.4042),
                _preset(term, palette, 'Sydney', -33.8688, 151.2093),
              ],
            ),
          ),
        ]),
        _section(palette, 'CLOCK', [
          _row(
            palette,
            'mode',
            Text(
              term.trackingLive && term.timeOffsetHours == 0
                  ? 'live'
                  : 'offset ${term.timeOffsetHours >= 0 ? '+' : ''}'
                        '${term.timeOffsetHours} h',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: term.trackingLive && term.timeOffsetHours == 0
                    ? palette.ok
                    : palette.warn,
              ),
            ),
          ),
          _row(
            palette,
            'shift',
            Row(
              children: [
                _miniButton(palette, '−6h', () => term.shiftTime(-6)),
                const SizedBox(width: 5),
                _miniButton(palette, '−1h', () => term.shiftTime(-1)),
                const SizedBox(width: 5),
                _miniButton(palette, '+1h', () => term.shiftTime(1)),
                const SizedBox(width: 5),
                _miniButton(palette, '+6h', () => term.shiftTime(6)),
                const SizedBox(width: 5),
                _miniButton(palette, 'NOW', term.resetTime, accent: true),
              ],
            ),
          ),
        ]),
        _section(palette, 'SESSION', [
          _row(
            palette,
            'observer',
            Text(
              term.observer,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.bright,
              ),
            ),
          ),
          _row(
            palette,
            'notes',
            Text(
              '${term.notes.length} stored',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
          _row(
            palette,
            'catalogue',
            Text(
              '${term.stars.length} objects · ${term.visibleCount} above horizon',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
        ]),
        _section(palette, 'MOON', [
          _row(
            palette,
            'phase',
            Text(
              '${term.moonGlyphValue}  ${term.moonPhaseLabel}',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
          _row(
            palette,
            'cycle',
            Text(
              '${(term.moonPhaseValue * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.mid,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'STARLIGHT TERMINAL v1.0.0\n'
            'local ephemeris · 41-star catalogue · everything on-device',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9.5,
              height: 1.7,
              color: palette.dim,
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(Palette palette, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
            child: Text(
              ruleLine(title, 40),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: palette.mid,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _row(Palette palette, String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  color: palette.dim,
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: value),
          ),
        ],
      ),
    );
  }

  Widget _paletteSwatches(TerminalController term, Palette palette) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in Palette.all)
          InkWell(
            onTap: () => term.setPalette(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(
                  color: p.id == palette.id ? p.bright : palette.line,
                  width: p.id == palette.id ? 1.4 : 1,
                ),
                color: p.id == palette.id
                    ? p.bright.withValues(alpha: 0.10)
                    : Colors.transparent,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, color: p.bright),
                  const SizedBox(width: 6),
                  Text(
                    p.label,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                      color: p.id == palette.id ? p.bright : palette.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _switch(
    Palette palette,
    bool on,
    VoidCallback onTap, {
    required String onLabel,
    required String offLabel,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: on ? palette.mid : palette.line),
          color: on ? palette.mid.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          on ? onLabel : offLabel,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: on ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Widget _miniButton(
    Palette palette,
    String label,
    VoidCallback onTap, {
    bool accent = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: accent ? palette.mid : palette.line),
          color: accent
              ? palette.mid.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: accent ? palette.bright : palette.mid,
          ),
        ),
      ),
    );
  }

  Widget _preset(
    TerminalController term,
    Palette palette,
    String name,
    double lat,
    double lon,
  ) {
    final active =
        (term.latitude - lat).abs() < 0.01 &&
        (term.longitude - lon).abs() < 0.01;
    return InkWell(
      onTap: () => term.setSite(lat, lon, name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: active ? palette.mid : palette.line),
          color: active
              ? palette.mid.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Text(
          name,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9,
            letterSpacing: 0.5,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }
}
