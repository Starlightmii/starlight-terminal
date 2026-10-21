import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Every background effect the terminal can render.
enum EffectKind {
  matrix,
  diffusion,
  layers,
  plasma,
  wireframe,
  starfield,
  gridwarp,
  ripple,
  aurora,
  circuit,
  bloomfield,
  glyphrain,
  none,
}

/// Live, user-tunable parameters shared by all effects.
///
/// Persisted alongside the palette, and mirrored to `effects` commands.
@immutable
class EffectParams {
  const EffectParams({
    this.kind = EffectKind.matrix,
    this.intensity = 0.6,
    this.speed = 1.0,
    this.density = 0.7,
    this.scale = 1.0,
    this.chroma = 0.5,
    this.grain = 0.0,
    this.hue = 0.0,
    this.bloom = 0.35,
    this.warp = 0.5,
  });

  final EffectKind kind;

  /// 0..1 — how loud the effect is against the content.
  final double intensity;

  /// 0.1..3 — animation rate multiplier.
  final double speed;

  /// 0..1 — element count (rain columns, blob count, layer count).
  final double density;

  /// 0.4..2.5 — spatial frequency.
  final double scale;

  /// 0..1 — colour separation / aberration strength.
  final double chroma;

  /// 0..1 — film grain / noise amount.
  final double grain;

  /// 0..1 — rotates the effect's colour ramp around the palette.
  final double hue;

  /// 0..1 — glow strength around bright features.
  final double bloom;

  /// 0..1 — geometric distortion / curvature.
  final double warp;

  EffectParams copyWith({
    EffectKind? kind,
    double? intensity,
    double? speed,
    double? density,
    double? scale,
    double? chroma,
    double? grain,
    double? hue,
    double? bloom,
    double? warp,
  }) {
    return EffectParams(
      kind: kind ?? this.kind,
      intensity: intensity ?? this.intensity,
      speed: speed ?? this.speed,
      density: density ?? this.density,
      scale: scale ?? this.scale,
      chroma: chroma ?? this.chroma,
      grain: grain ?? this.grain,
      hue: hue ?? this.hue,
      bloom: bloom ?? this.bloom,
      warp: warp ?? this.warp,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'intensity': intensity,
        'speed': speed,
        'density': density,
        'scale': scale,
        'chroma': chroma,
        'grain': grain,
        'hue': hue,
        'bloom': bloom,
        'warp': warp,
      };

  static EffectParams fromJson(Map<String, dynamic>? j) {
    if (j == null) return const EffectParams();
    return EffectParams(
      kind: EffectKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => EffectKind.matrix,
      ),
      intensity: (j['intensity'] as num?)?.toDouble() ?? 0.6,
      speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
      density: (j['density'] as num?)?.toDouble() ?? 0.7,
      scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
      chroma: (j['chroma'] as num?)?.toDouble() ?? 0.5,
      grain: (j['grain'] as num?)?.toDouble() ?? 0.0,
      hue: (j['hue'] as num?)?.toDouble() ?? 0.0,
      bloom: (j['bloom'] as num?)?.toDouble() ?? 0.35,
      warp: (j['warp'] as num?)?.toDouble() ?? 0.5,
    );
  }

  static const Map<EffectKind, String> labels = {
    EffectKind.circuit: 'CIRCUIT',
    EffectKind.bloomfield: 'BLOOM',
    EffectKind.glyphrain: 'GLYPH',
    EffectKind.matrix: 'MATRIX',
    EffectKind.diffusion: 'DIFFUSION',
    EffectKind.layers: 'LAYERS',
    EffectKind.plasma: 'PLASMA',
    EffectKind.wireframe: 'WIREFRAME',
    EffectKind.starfield: 'STARFIELD',
    EffectKind.gridwarp: 'GRIDWARP',
    EffectKind.ripple: 'RIPPLE',
    EffectKind.aurora: 'AURORA',
    EffectKind.none: 'NONE',
  };

  static const Map<EffectKind, String> descriptions = {
    EffectKind.circuit: 'Traces racing along a hardware lattice.',
    EffectKind.bloomfield: 'Soft drifting light blooms that breathe.',
    EffectKind.glyphrain: 'Falling ASCII glyphs in a slow rain.',
    EffectKind.matrix: 'Falling glyph rain. The canonical terminal effect.',
    EffectKind.diffusion: 'Slow reaction–diffusion field behind the glass.',
    EffectKind.layers: 'Random parallax layers, drifting and re-seeding.',
    EffectKind.plasma: 'Sinusoidal plasma with chromatic separation.',
    EffectKind.wireframe: 'Terrain mesh scroll, horizon perspective.',
    EffectKind.starfield: 'Hyperspace streak field, depth-sorted.',
    EffectKind.gridwarp: 'Perspective grid bending into a gravity well.',
    EffectKind.ripple: 'Concentric interference rings from moving centres.',
    EffectKind.aurora: 'Layered curtains of drifting colour.',
    EffectKind.none: 'Plain starfield only.',
  };
}

/// Hosts an effect with a repaint-driven ticker.
class EffectCanvas extends StatefulWidget {
  const EffectCanvas({
    super.key,
    required this.palette,
    required this.params,
    required this.animate,
  });

  final Palette palette;
  final EffectParams params;
  final bool animate;

  @override
  State<EffectCanvas> createState() => _EffectCanvasState();
}

class _EffectCanvasState extends State<EffectCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  EffectKind? _seededFor;
  _MatrixState _matrix = _MatrixState.empty();
  _LayerState _layers = _LayerState.empty();

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..value = 0;
    if (widget.animate) _t.repeat();
  }

  @override
  void didUpdateWidget(covariant EffectCanvas old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_t.isAnimating) {
      _t.repeat();
    } else if (!widget.animate && _t.isAnimating) {
      _t.stop();
    }
    if (old.params.kind != widget.params.kind) {
      _seededFor = null;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.params.kind == EffectKind.none) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _EffectPainter(
            palette: widget.palette,
            params: widget.params,
            ticker: widget.animate ? _t : null,
            ensureSeed: (size) {
              if (_seededFor == widget.params.kind) return;
              _seededFor = widget.params.kind;
              _matrix = _MatrixState.seed(size, widget.params);
              _layers = _LayerState.build(widget.params);
            },
            matrix: () => _matrix,
            layers: () => _layers,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Matrix ────────────────────────────────────────────────────────────────

class _MatrixColumn {
  _MatrixColumn(this.x, this.y, this.len, this.speed, this.glyphSeed);
  double x;
  double y;
  final int len;
  final double speed;
  final int glyphSeed;
}

class _MatrixState {
  _MatrixState(this.columns, this.fontSize);
  final List<_MatrixColumn> columns;
  final double fontSize;

  static _MatrixState empty() => _MatrixState(<_MatrixColumn>[], 12);

  static _MatrixState seed(Size size, EffectParams p) {
    final rnd = math.Random(42);
    final fontSize = 10.0 + p.scale * 4.0;
    final spacing = fontSize * 1.25;
    final cols = (size.width / spacing).floor().clamp(1, 400);
    final count = (cols * p.density).round().clamp(1, 400);
    final columns = List<_MatrixColumn>.generate(count, (i) {
      return _MatrixColumn(
        (i * (cols / count) + rnd.nextDouble()) * spacing,
        rnd.nextDouble() * size.height * 2 - size.height,
        6 + rnd.nextInt(16),
        26.0 + rnd.nextDouble() * 70.0,
        rnd.nextInt(9999),
      );
    });
    return _MatrixState(columns, fontSize);
  }
}

// ── Layers ────────────────────────────────────────────────────────────────

class _Shard {
  _Shard(this.x, this.y, this.w, this.h, this.depth, this.rot);
  final double x;
  final double y;
  final double w;
  final double h;
  final double depth;
  final double rot;
}

class _LayerState {
  _LayerState(this.shards, this.seed);
  final List<_Shard> shards;
  final int seed;

  static _LayerState empty() => _LayerState(<_Shard>[], 0);

  static _LayerState build(EffectParams p) {
    final rnd = math.Random(7);
    final count = (6 + (p.density * 26)).round();
    final shards = List<_Shard>.generate(count, (_) {
      return _Shard(
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.06 + rnd.nextDouble() * 0.34,
        0.02 + rnd.nextDouble() * 0.16,
        0.25 + rnd.nextDouble() * 0.75,
        (rnd.nextDouble() - 0.5) * 0.1,
      );
    });
    return _LayerState(shards, rnd.nextInt(9999));
  }
}

// ── Painter ───────────────────────────────────────────────────────────────

class _EffectPainter extends CustomPainter {
  _EffectPainter({
    required this.palette,
    required this.params,
    required this.ticker,
    required this.ensureSeed,
    required this.matrix,
    required this.layers,
  }) : super(repaint: ticker);

  final Palette palette;
  final EffectParams params;
  final Animation<double>? ticker;
  final void Function(Size size) ensureSeed;
  final _MatrixState Function() matrix;
  final _LayerState Function() layers;

  @override
  void paint(Canvas canvas, Size size) {
    ensureSeed(size);
    final t = (ticker?.value ?? 0.0) * params.speed;

    switch (params.kind) {
      case EffectKind.matrix:
        _paintMatrix(canvas, size, t);
      case EffectKind.diffusion:
        _paintDiffusion(canvas, size, t);
      case EffectKind.layers:
        _paintLayers(canvas, size, t);
      case EffectKind.plasma:
        _paintPlasma(canvas, size, t);
      case EffectKind.wireframe:
        _paintWireframe(canvas, size, t);
      case EffectKind.starfield:
        _paintStarfield(canvas, size, t);
      case EffectKind.gridwarp:
        _paintGridWarp(canvas, size, t);
      case EffectKind.ripple:
        _paintRipple(canvas, size, t);
      case EffectKind.aurora:
        _paintAurora(canvas, size, t);
      case EffectKind.none:
        break;
    }

    if (params.grain > 0.01) _paintGrain(canvas, size, t);
  }

  void _paintMatrix(Canvas canvas, Size size, double t) {
    final state = matrix();
    if (state.columns.isEmpty) return;

    // One TextPainter per column would be expensive; draw glyphs as short
    // strokes instead — at these sizes it reads identically and stays smooth.
    final trail = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;

    final elapsed = t * 300.0; // virtual pixels travelled

    for (final c in state.columns) {
      final span = size.height + c.len * state.fontSize * 1.2;
      var head = (c.y + elapsed * (c.speed / 60.0)) % span;
      if (head < 0) head += span;
      head -= size.height * 0.5;

      for (var i = 0; i < c.len; i++) {
        final y = head - i * state.fontSize;
        if (y < -state.fontSize || y > size.height) continue;
        final fade = (1.0 - i / c.len) * params.intensity;
        final alpha = (fade * 0.85).clamp(0.0, 1.0);
        if (alpha < 0.02) continue;
        trail.color = (i == 0 ? palette.bright : palette.mid)
            .withValues(alpha: i == 0 ? alpha : alpha * 0.55);
        // A deterministic pseudo-glyph: two short strokes per cell.
        final g = (c.glyphSeed + i * 37) % 4;
        final gx = c.x;
        switch (g) {
          case 0:
            canvas.drawLine(
              Offset(gx, y),
              Offset(gx + state.fontSize * 0.55, y),
              trail,
            );
          case 1:
            canvas.drawLine(
              Offset(gx, y),
              Offset(gx, y + state.fontSize * 0.7),
              trail,
            );
          case 2:
            canvas.drawLine(
              Offset(gx, y),
              Offset(gx + state.fontSize * 0.5, y + state.fontSize * 0.6),
              trail,
            );
          default:
            canvas.drawLine(
              Offset(gx, y + state.fontSize * 0.5),
              Offset(gx + state.fontSize * 0.6, y + state.fontSize * 0.5),
              trail,
            );
        }
      }
    }
  }

  void _paintDiffusion(Canvas canvas, Size size, double t) {
    // Three coarse scrolling radial fields composited additively — reads as a
    // reaction–diffusion / ink-in-water surface at a fraction of the cost.
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
    for (var i = 0; i < 3; i++) {
      final phase = t * math.pi * 2 * (0.15 + i * 0.07) + i * 2.1;
      final cx = size.width * (0.5 + 0.34 * math.sin(phase * 0.9 + i));
      final cy = size.height * (0.5 + 0.30 * math.cos(phase * 0.7 + i * 1.3));
      final r = size.shortestSide * (0.30 + 0.22 * math.sin(phase * 0.5)) * params.scale;
      final color = (i.isEven ? palette.mid : palette.bright)
          .withValues(alpha: 0.10 * params.intensity);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
    canvas.restore();
  }

  void _paintLayers(Canvas canvas, Size size, double t) {
    final state = layers();
    for (final s in state.shards) {
      final drift = t * 60 * s.depth * params.speed;
      final x = ((s.x * size.width + drift) % (size.width * 1.4)) - size.width * 0.2;
      final y = s.y * size.height + math.sin(t * math.pi * 2 + s.x * 12) * 18 * s.depth;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(s.rot);
      final w = s.w * size.width * params.scale;
      final h = s.h * size.height;
      final alpha = (0.05 + s.depth * 0.13) * params.intensity;
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + s.depth
          ..color = (s.depth > 0.6 ? palette.bright : palette.line)
              .withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  void _paintPlasma(Canvas canvas, Size size, double t) {
    // Coarse grid of plasma, drawn as small tiles. 24×24 keeps the frame cheap
    // while the chromatic offsets give it the interference look.
    const cells = 26;
    final cw = size.width / cells;
    final ch = size.height / (cells * 0.8);
    final phase = t * math.pi * 2;

    for (var gy = 0; gy < cells; gy++) {
      for (var gx = 0; gx < cells; gx++) {
        final nx = gx / cells;
        final ny = gy / cells;
        final v = math.sin(nx * 6 * params.scale + phase) +
            math.sin(ny * 5 * params.scale - phase * 0.8) +
            math.sin((nx + ny) * 4 * params.scale + phase * 0.6);
        final n = ((v + 3) / 6).clamp(0.0, 1.0);
        if (n < 0.42) continue;
        final alpha = ((n - 0.42) / 0.58) * 0.34 * params.intensity;
        final base = palette.mid.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(gx * cw, gy * ch, cw + 0.5, ch + 0.5),
          Paint()..color = base,
        );
        // Chromatic separation.
        if (params.chroma > 0.05) {
          final off = params.chroma * 3.2;
          canvas.drawRect(
            Rect.fromLTWH(gx * cw + off, gy * ch, cw, ch),
            Paint()
              ..color = palette.bright.withValues(alpha: alpha * 0.30)
              ..blendMode = BlendMode.plus,
          );
        }
      }
    }
  }

  void _paintWireframe(Canvas canvas, Size size, double t) {
    const rows = 16;
    final horizon = size.height * 0.42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    // Perspective horizontal lines, scrolling toward the viewer.
    for (var i = 0; i < rows; i++) {
      final f = (i / rows + t * 0.35) % 1.0;
      final y = horizon + math.pow(f, 2.2) * (size.height - horizon);
      final alpha = (1 - f) * 0.22 * params.intensity + 0.03;
      paint.color = palette.mid.withValues(alpha: alpha);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Converging verticals.
    final cx = size.width / 2;
    for (var i = -10; i <= 10; i++) {
      paint.color = palette.line.withValues(alpha: 0.22 * params.intensity);
      canvas.drawLine(
        Offset(cx + i * size.width * 0.14, size.height),
        Offset(cx + i * 3.0, horizon),
        paint,
      );
    }

    // Bright horizon.
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..strokeWidth = 1.4
        ..color = palette.bright.withValues(alpha: 0.30 * params.intensity),
    );
  }

  // ── starfield / hyperspace ─────────────────────────────────────────────

  /// Depth-sorted streak field. Each particle has a fixed angle and speed;
  /// its radius is `(phase + t) mod 1`, so particles recycle toward the centre
  /// without any per-frame allocation.
  void _paintStarfield(Canvas canvas, Size size, double t) {
    final rnd = math.Random(20240);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.sqrt(cx * cx + cy * cy);
    final count = (params.density * 220 + 30).round();
    final paint = Paint()..strokeWidth = 1.4;
    final warp = 0.4 + params.warp * 2.2;

    for (var i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 0.08 + rnd.nextDouble() * 0.35;
      final phase = rnd.nextDouble();
      final bright = 0.25 + rnd.nextDouble() * 0.75;

      var p = (phase + t * speed) % 1.0;
      // Bias to the outer half so the centre doesn't flood.
      p = math.pow(p, 0.65).toDouble();
      final r = p * maxR;
      final dx = math.cos(angle) * r;
      final dy = math.sin(angle) * r;

      // Streaks lengthen with distance from the vanishing point.
      final len = (r / maxR) * 14 * warp * params.speed;
      final alpha = (bright * params.intensity * (r / maxR)).clamp(0.0, 1.0);
      if (alpha < 0.02) continue;

      paint.color = palette.bright.withValues(alpha: alpha);
      canvas.drawLine(
        Offset(cx + dx, cy + dy),
        Offset(
          cx + dx - math.cos(angle) * len,
          cy + dy - math.sin(angle) * len,
        ),
        paint,
      );

      if (params.bloom > 0.15 && bright > 0.9) {
        canvas.drawCircle(
          Offset(cx + dx, cy + dy),
          1.8,
          Paint()
            ..color = palette.bright
                .withValues(alpha: alpha * params.bloom * 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  // ── grid warp ──────────────────────────────────────────────────────────

  /// A perspective floor grid that bends toward a drifting gravity well.
  void _paintGridWarp(Canvas canvas, Size size, double t) {
    final horizon = size.height * (0.35 + params.warp * 0.2);
    final well = Offset(
      size.width * (0.5 + 0.22 * math.sin(t * 0.7)),
      horizon + size.height * 0.32,
    );
    final paint = Paint()..strokeWidth = 1;
    final alpha = (params.intensity * 0.5).clamp(0.0, 1.0);

    // Horizontal rows, spaced by a perspective curve.
    const rows = 22;
    for (var i = 1; i <= rows; i++) {
      final f = i / rows;
      final y = horizon + (size.height - horizon) * (f * f);
      final rowAlpha = alpha * (0.25 + f * 0.75);
      paint.color = palette.mid.withValues(alpha: rowAlpha);
      final path = Path()..moveTo(0, y);
      const segs = 16;
      for (var s = 1; s <= segs; s++) {
        final x = size.width * s / segs;
        // Pull toward the well; stronger lower on screen and nearer in x.
        final dx = x - well.dx;
        final dy = y - well.dy;
        final d = math.sqrt(dx * dx + dy * dy) + 1;
        final pull = (params.warp * 26000) / (d * d);
        path.lineTo(x - dx / d * pull, y - dy / d * pull);
      }
      canvas.drawPath(path, paint);
    }

    // Vertical spokes converging on the vanishing point.
    const cols = 15;
    for (var c = 0; c <= cols; c++) {
      final f = c / cols;
      paint.color = palette.mid.withValues(alpha: alpha * 0.7);
      final topX = size.width * f;
      final bottomX = size.width * (0.5 + (f - 0.5) * 2.4);
      final path = Path()..moveTo(topX, horizon);
      const segs = 8;
      for (var s = 1; s <= segs; s++) {
        final g = s / segs;
        final x = topX + (bottomX - topX) * g;
        final y = horizon + (size.height - horizon) * (g * g);
        final dx = x - well.dx;
        final dy = y - well.dy;
        final d = math.sqrt(dx * dx + dy * dy) + 1;
        final pull = (params.warp * 24000) / (d * d);
        path.lineTo(x - dx / d * pull, y - dy / d * pull);
      }
      canvas.drawPath(path, paint);
    }

    if (params.bloom > 0.05) {
      canvas.drawCircle(
        well,
        6 + params.bloom * 16,
        Paint()
          ..color = palette.bright
              .withValues(alpha: params.bloom * 0.18 * params.intensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  // ── ripple ─────────────────────────────────────────────────────────────

  /// Interference rings from two moving centres — cheap, and reads as a
  /// liquid surface behind the glass.
  void _paintRipple(Canvas canvas, Size size, double t) {
    final centres = <Offset>[
      Offset(
        size.width * (0.5 + 0.3 * math.sin(t * 0.6)),
        size.height * (0.5 + 0.25 * math.cos(t * 0.45)),
      ),
      Offset(
        size.width * (0.5 + 0.25 * math.cos(t * 0.35)),
        size.height * (0.5 + 0.3 * math.sin(t * 0.5)),
      ),
    ];
    final maxR = math.min(size.width, size.height) * 0.7;
    final rings = (10 + params.density * 22).round();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var ci = 0; ci < centres.length; ci++) {
      final c = centres[ci];
      for (var i = 0; i < rings; i++) {
        final phase = i / rings;
        final r = ((phase + t * 0.12 * (ci == 0 ? 1 : -1)) % 1.0) * maxR;
        if (r < 2) continue;
        final fade = 1.0 - r / maxR;
        final alpha =
            (fade * params.intensity * (ci == 0 ? 0.5 : 0.35)).clamp(0.0, 1.0);
        if (alpha < 0.02) continue;
        paint.color = (ci == 0 ? palette.mid : palette.bright)
            .withValues(alpha: alpha);
        canvas.drawCircle(c, r, paint);
      }
    }
  }

  // ── aurora ─────────────────────────────────────────────────────────────

  /// Vertical curtains. Each curtain is a wobbly vertical gradient strip whose
  /// phase drifts, which is enough to read as aurora at low opacity.
  void _paintAurora(Canvas canvas, Size size, double t) {
    final curtains = (3 + params.density * 6).round();
    final rect = Offset.zero & size;

    for (var c = 0; c < curtains; c++) {
      final seed = c * 37.7;
      final xBase = size.width * ((c + 0.5) / curtains);
      final drift = math.sin(t * 0.4 + seed) * size.width * 0.08;
      final height = size.height * (0.45 + 0.3 * math.sin(t * 0.3 + seed));
      final top = size.height * 0.08 + height * 0.1;

      final path = Path();
      final steps = 18;
      for (var i = 0; i <= steps; i++) {
        final f = i / steps;
        final x = xBase +
            drift +
            math.sin(f * 3.4 + t * 0.8 + seed) * size.width * 0.05;
        final y = top + f * height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      // Close the curtain back down the other side for a fillable shape.
      for (var i = steps; i >= 0; i--) {
        final f = i / steps;
        final x = xBase +
            drift +
            size.width * 0.06 +
            math.sin(f * 3.4 + t * 0.8 + seed) * size.width * 0.05;
        final y = top + f * height;
        path.lineTo(x, y);
      }
      path.close();

      final baseHue = (params.hue + c * 0.13) % 1.0;
      final tint = Color.lerp(palette.mid, palette.bright, baseHue)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: 0.0),
              tint.withValues(alpha: 0.22 * params.intensity),
              palette.ok.withValues(alpha: 0.10 * params.intensity),
              tint.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.35, 0.7, 1.0],
          ).createShader(rect),
      );
    }
  }

  void _paintGrain(Canvas canvas, Size size, double t) {
    final rnd = math.Random((t * 60).floor());
    final n = (params.grain * 900).round();
    final paint = Paint()..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      paint.color = palette.bright.withValues(
        alpha: params.grain * 0.10 * rnd.nextDouble(),
      );
      canvas.drawPoints(
        ui.PointMode.points,
        [Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height)],
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) =>
      old.palette != palette ||
      old.params != params ||
      old.ticker != ticker;
}
