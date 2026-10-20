import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Every background effect the terminal can render.
enum EffectKind { matrix, diffusion, layers, plasma, wireframe, none }

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

  EffectParams copyWith({
    EffectKind? kind,
    double? intensity,
    double? speed,
    double? density,
    double? scale,
    double? chroma,
    double? grain,
  }) {
    return EffectParams(
      kind: kind ?? this.kind,
      intensity: intensity ?? this.intensity,
      speed: speed ?? this.speed,
      density: density ?? this.density,
      scale: scale ?? this.scale,
      chroma: chroma ?? this.chroma,
      grain: grain ?? this.grain,
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
    );
  }

  static const Map<EffectKind, String> labels = {
    EffectKind.matrix: 'MATRIX',
    EffectKind.diffusion: 'DIFFUSION',
    EffectKind.layers: 'LAYERS',
    EffectKind.plasma: 'PLASMA',
    EffectKind.wireframe: 'WIREFRAME',
    EffectKind.none: 'NONE',
  };

  static const Map<EffectKind, String> descriptions = {
    EffectKind.matrix: 'Falling glyph rain. The canonical terminal effect.',
    EffectKind.diffusion: 'Slow reaction–diffusion field behind the glass.',
    EffectKind.layers: 'Random parallax layers, drifting and re-seeding.',
    EffectKind.plasma: 'Sinusoidal plasma with chromatic separation.',
    EffectKind.wireframe: 'Terrain mesh scroll, horizon perspective.',
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
