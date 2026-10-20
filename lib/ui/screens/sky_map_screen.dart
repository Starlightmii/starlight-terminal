import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue.dart';
import '../../core/console_engine.dart';
import '../../core/memory.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';

/// Polar sky chart: zenith at the centre, horizon at the rim, N at the top.
class SkyMapScreen extends StatelessWidget {
  const SkyMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final studio = context.watch<StudioController>();
    final palette = term.palette;

    return Column(
      children: [
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'AZIMUTHAL PROJECTION',
            accent: true,
            padding: const EdgeInsets.all(8),
            trailing: Text(
              '${term.visibleCount}/${term.stars.length} UP',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: palette.ok,
              ),
            ),
            child: term.stage != BootStage.ready
                ? _bootPlaceholder(palette, term)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapDown: (details) => _handleTap(
                          context,
                          term,
                          details.localPosition,
                          Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                        child: CustomPaint(
                          painter: _SkyMapPainter(
                            stars: term.stars,
                            palette: palette,
                            selectedId: term.selectedStar?.id,
                            reducedMotion: term.reduceMotion,
                            memories: studio.memory.all,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        _selectedSheet(context, term, palette),
        const SizedBox(height: 8),
        _memoryStrip(studio, palette),
      ],
    );
  }

  /// Memories anchored to a sky object, newest first, above the detail sheet.
  Widget _memoryStrip(StudioController studio, Palette palette) {
    final anchored = studio.memory.anchored;
    final total = studio.memory.length;
    final plotted = total;
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MEMORY ANCHORS',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: palette.dim,
                ),
              ),
              const Spacer(),
              Text(
                '$plotted plotted · ${anchored.length} pinned · $total stored',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8,
                  color: palette.dim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (anchored.isEmpty)
            Text(
              'memories from pi and bot chats plot automatically · anchor one to a star to pin it',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.dim.withValues(alpha: 0.8),
              ),
            )
          else
            SizedBox(
              height: 26,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: anchored.length,
                itemBuilder: (context, i) {
                  final m = anchored[i];
                  final star = m.starId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Row(
                      children: [
                        Text(
                          '★',
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8,
                            color: palette.warn,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          (star ?? '').toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8,
                            color: palette.bright,
                          ),
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            m.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 8,
                              color: palette.dim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _bootPlaceholder(Palette palette, TerminalController term) {
    return Center(
      child: Text(
        'solving coordinate frames…',
        style: TextStyle(fontFamily: 'Mono', fontSize: 12, color: palette.dim),
      ),
    );
  }

  Widget _selectedSheet(
    BuildContext context,
    TerminalController term,
    Palette palette,
  ) {
    final star = term.selectedStar;
    if (star == null) {
      return TermPanel(
        palette: palette,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              'tap a plotted star to inspect it',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.dim,
              ),
            ),
          ],
        ),
      );
    }

    final above = star.altitude > 0;
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      title: star.name.toUpperCase(),
      trailing: InkWell(
        onTap: term.clearSelection,
        child: Text(
          'CLOSE',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9,
            letterSpacing: 1.2,
            color: palette.dim,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: spectralColor(star.spectral),
                  boxShadow: [
                    BoxShadow(
                      color: spectralColor(
                        star.spectral,
                      ).withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  star.bayer,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11,
                    color: palette.mid,
                  ),
                ),
              ),
              Text(
                fmtMag(star.magnitude),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv(
            palette,
            'altitude',
            '${star.altitude.toStringAsFixed(1)}° ${above ? '· up' : '· below'}',
          ),
          _kv(
            palette,
            'azimuth',
            '${star.azimuth.toStringAsFixed(0)}° ${compassPoint(star.azimuth)}',
          ),
          _kv(
            palette,
            'ra/dec',
            '${fmtRa(star.raHours)}  ${fmtDec(star.decDegrees)}',
          ),
          _kv(
            palette,
            'spectral',
            '${star.spectral} · ${fmtDistance(star.distanceLy)}',
          ),
        ],
      ),
    );
  }

  Widget _kv(Palette palette, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              k,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10.5,
                color: palette.dim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10.5,
                color: palette.mid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    TerminalController term,
    Offset local,
    Size size,
  ) {
    if (term.stars.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 26;
    if (radius <= 0) return;

    Star? best;
    var bestDist = 26.0;
    for (final s in term.stars) {
      if (s.altitude <= 0) continue;
      final p = _project(s, center, radius);
      final d = (p - local).distance;
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    if (best != null) {
      term.selectStar(best);
    }
  }
}

/// Project a star into the disc: alt 90° → centre, alt 0° → rim.
Offset _project(Star s, Offset center, double radius) {
  final r = radius * (1 - (s.altitude.clamp(0.0, 90.0) / 90.0));
  // Azimuth measured clockwise from north; screen y grows downward.
  final theta = (s.azimuth - 90) * math.pi / 180.0;
  return Offset(
    center.dx + r * math.cos(theta),
    center.dy + r * math.sin(theta),
  );
}

class _SkyMapPainter extends CustomPainter {
  _SkyMapPainter({
    required this.stars,
    required this.palette,
    required this.selectedId,
    required this.reducedMotion,
    this.memories = const <Memory>[],
  });

  final List<Star> stars;
  final Palette palette;
  final String? selectedId;
  final bool reducedMotion;

  /// Memories anchored to a star, drawn as halos around that star.
  final List<Memory> memories;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 26;
    if (radius <= 0) return;

    _drawGrid(canvas, center, radius);
    _drawHorizonLabels(canvas, center, radius);
    _drawStars(canvas, center, radius);
    _drawMemories(canvas, center, radius);
    _drawZenith(canvas, center);
  }

  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = palette.line.withValues(alpha: 0.85);

    // Altitude rings every 30°.
    for (final alt in [30.0, 60.0]) {
      final r = radius * (1 - alt / 90.0);
      canvas.drawCircle(center, r, grid);
    }
    // Horizon rim, brighter.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = palette.mid.withValues(alpha: 0.75),
    );

    // Radial spokes every 45°.
    for (var az = 0; az < 360; az += 45) {
      final theta = (az - 90) * math.pi / 180.0;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * math.cos(theta),
          center.dy + radius * math.sin(theta),
        ),
        grid,
      );
    }

    // Altitude ring labels.
    for (final alt in [30.0, 60.0]) {
      final r = radius * (1 - alt / 90.0);
      _label(
        canvas,
        '${alt.toInt()}°',
        Offset(center.dx + 4, center.dy - r - 9),
        palette.dim,
        8.5,
      );
    }
  }

  void _drawHorizonLabels(Canvas canvas, Offset center, double radius) {
    const points = <String, double>{'N': 0, 'E': 90, 'S': 180, 'W': 270};
    points.forEach((label, az) {
      final theta = (az - 90) * math.pi / 180.0;
      final pos = Offset(
        center.dx + (radius + 14) * math.cos(theta),
        center.dy + (radius + 14) * math.sin(theta),
      );
      _label(
        canvas,
        label,
        Offset(pos.dx - 4, pos.dy - 6),
        az == 0 ? palette.bright : palette.mid,
        10,
        bold: true,
      );
    });
  }

  void _drawStars(Canvas canvas, Offset center, double radius) {
    // Draw dim stars first so bright ones land on top.
    final sorted = List<Star>.from(stars)
      ..sort((a, b) => b.magnitude.compareTo(a.magnitude));

    for (final s in sorted) {
      if (s.altitude <= 0) continue;

      // Size and alpha both scale with apparent brightness.
      final b = ((3.2 - s.magnitude) / 4.6).clamp(0.12, 1.0);
      final r = 0.9 + b * 4.4;
      final alpha = (0.35 + b * 0.65).clamp(0.0, 1.0);
      final tint = spectralColor(s.spectral);
      final pos = _project(s, center, radius);
      final isSelected = s.id == selectedId;

      // Glow halo.
      if (b > 0.45) {
        canvas.drawCircle(
          pos,
          r * 3.4,
          Paint()
            ..color = tint.withValues(alpha: alpha * 0.14)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      canvas.drawCircle(pos, r, Paint()..color = tint.withValues(alpha: alpha));

      if (isSelected) {
        canvas.drawCircle(
          pos,
          r + 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = palette.bright.withValues(alpha: 0.9),
        );
        canvas.drawCircle(
          pos,
          r + 13,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..color = palette.bright.withValues(alpha: 0.35),
        );
      }

      // Label the brightest handful only — keeps the disc readable.
      if (s.magnitude < 1.1 || isSelected) {
        _label(
          canvas,
          s.name,
          Offset(pos.dx + r + 5, pos.dy - 6),
          isSelected ? palette.bright : palette.mid.withValues(alpha: 0.85),
          9,
          bold: isSelected,
        );
      }
    }
  }

  void _drawZenith(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      2.2,
      Paint()..color = palette.bright.withValues(alpha: 0.55),
    );
    _label(
      canvas,
      'ZENITH',
      Offset(center.dx + 6, center.dy + 4),
      palette.dim,
      8,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double size, {
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  /// Halos around stars that carry memories, sized by how many are attached.
  ///
  /// Memories that were never explicitly anchored to a sky object still need a
  /// home — otherwise every memory captured from a pi/bot chat would be stored
  /// but invisible here. Those are placed on a deterministic star (derived from
  /// the memory id) so the constellation is stable across rebuilds.
  void _drawMemories(Canvas canvas, Offset center, double radius) {
    if (memories.isEmpty || stars.isEmpty) return;
    final counts = <String, int>{};
    final up = stars.where((s) => s.altitude > 0).toList();
    if (up.isEmpty) return;
    for (final m in memories) {
      final id = m.starId;
      final target = (id != null && id.isNotEmpty)
          ? id
          : up[m.id.hashCode.abs() % up.length].id;
      counts[target] = (counts[target] ?? 0) + 1;
    }
    for (final s in stars) {
      final n = counts[s.id];
      if (n == null || s.altitude <= 0) continue;
      final pos = _project(s, center, radius);
      final r = 4.0 + math.min(n, 6) * 1.6;
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.warn.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        pos,
        r * 2.1,
        Paint()
          ..color = palette.warn.withValues(alpha: 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkyMapPainter old) =>
      old.palette != palette ||
      old.selectedId != selectedId ||
      old.reducedMotion != reducedMotion ||
      old.stars != stars ||
      old.memories.length != memories.length;
}
