import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Every background effect the terminal can render.
enum EffectKind {
  // ── classic phosphor ─────────────────────────────────────────────────
  matrix,
  glyphrain,
  neonrain,
  circuit,

  // ── fields & flow ────────────────────────────────────────────────────
  plasma,
  diffusion,
  chromaflow,
  aurora,
  bloomfield,

  // ── geometry ─────────────────────────────────────────────────────────
  wireframe,
  gridwarp,
  tunnel,
  kaleido,

  // ── particles ────────────────────────────────────────────────────────
  starfield,
  wormhole,
  sparks,
  metaballs,

  // ── signal / interference ────────────────────────────────────────────
  ripple,
  radar,
  lissajous,
  voronoi,

  // ── text & code ──────────────────────────────────────────────────────
  asciiwave,
  dither,
  spectrum,
  hologram,
  layers,

  none,
}

/// Broad grouping used by the FX browser so 27 renderers stay navigable.
enum EffectFamily { phosphor, fields, geometry, particles, signal, text, off }

const Map<EffectKind, EffectFamily> kEffectFamily = {
  EffectKind.matrix: EffectFamily.phosphor,
  EffectKind.glyphrain: EffectFamily.phosphor,
  EffectKind.neonrain: EffectFamily.phosphor,
  EffectKind.circuit: EffectFamily.phosphor,
  EffectKind.plasma: EffectFamily.fields,
  EffectKind.diffusion: EffectFamily.fields,
  EffectKind.chromaflow: EffectFamily.fields,
  EffectKind.aurora: EffectFamily.fields,
  EffectKind.bloomfield: EffectFamily.fields,
  EffectKind.wireframe: EffectFamily.geometry,
  EffectKind.gridwarp: EffectFamily.geometry,
  EffectKind.tunnel: EffectFamily.geometry,
  EffectKind.kaleido: EffectFamily.geometry,
  EffectKind.starfield: EffectFamily.particles,
  EffectKind.wormhole: EffectFamily.particles,
  EffectKind.sparks: EffectFamily.particles,
  EffectKind.metaballs: EffectFamily.particles,
  EffectKind.ripple: EffectFamily.signal,
  EffectKind.radar: EffectFamily.signal,
  EffectKind.lissajous: EffectFamily.signal,
  EffectKind.voronoi: EffectFamily.signal,
  EffectKind.asciiwave: EffectFamily.text,
  EffectKind.dither: EffectFamily.text,
  EffectKind.spectrum: EffectFamily.text,
  EffectKind.hologram: EffectFamily.text,
  EffectKind.layers: EffectFamily.text,
  EffectKind.none: EffectFamily.off,
};

const Map<EffectFamily, String> kEffectFamilyLabel = {
  EffectFamily.phosphor: 'PHOSPHOR',
  EffectFamily.fields: 'FIELDS',
  EffectFamily.geometry: 'GEOMETRY',
  EffectFamily.particles: 'PARTICLES',
  EffectFamily.signal: 'SIGNAL',
  EffectFamily.text: 'TEXT',
  EffectFamily.off: 'OFF',
};

/// One-click looks: a fully-specified parameter set the operator can recall.
@immutable
class EffectPreset {
  const EffectPreset(this.name, this.params);
  final String name;
  final EffectParams params;
}

/// Hand-tuned presets that show off the range without any fiddling.
const List<EffectPreset> kEffectPresets = [
  EffectPreset('TERMINAL', EffectParams(kind: EffectKind.matrix, intensity: 0.6)),
  EffectPreset(
    'NEON CITY',
    EffectParams(
      kind: EffectKind.neonrain,
      intensity: 0.85,
      speed: 1.4,
      density: 0.85,
      spectrum: 0.75,
      bloom: 0.7,
      grain: 0.06,
    ),
  ),
  EffectPreset(
    'DEEP FIELD',
    EffectParams(
      kind: EffectKind.wormhole,
      intensity: 0.9,
      speed: 0.9,
      density: 0.8,
      warp: 0.85,
      bloom: 0.8,
      spectrum: 0.35,
    ),
  ),
  EffectPreset(
    'GAS GIANT',
    EffectParams(
      kind: EffectKind.metaballs,
      intensity: 0.8,
      speed: 0.55,
      density: 0.7,
      spectrum: 0.9,
      bloom: 0.9,
      chroma: 0.45,
    ),
  ),
  EffectPreset(
    'RAINBOW STATIC',
    EffectParams(
      kind: EffectKind.spectrum,
      intensity: 0.75,
      speed: 1.1,
      density: 0.8,
      spectrum: 1.0,
      grain: 0.22,
    ),
  ),
  EffectPreset(
    'WARP TUNNEL',
    EffectParams(
      kind: EffectKind.tunnel,
      intensity: 0.85,
      speed: 1.6,
      density: 0.6,
      spectrum: 0.6,
      warp: 1.0,
      bloom: 0.5,
    ),
  ),
  EffectPreset(
    'CATHODE',
    EffectParams(
      kind: EffectKind.glyphrain,
      intensity: 0.5,
      speed: 0.8,
      density: 0.6,
      grain: 0.14,
      chroma: 0.15,
    ),
  ),
  EffectPreset(
    'AURORA GLASS',
    EffectParams(
      kind: EffectKind.aurora,
      intensity: 0.7,
      speed: 0.6,
      density: 0.8,
      spectrum: 0.55,
      bloom: 0.6,
    ),
  ),
  EffectPreset(
    'BLUEPRINT',
    EffectParams(
      kind: EffectKind.kaleido,
      intensity: 0.6,
      speed: 0.7,
      density: 0.5,
      scale: 1.4,
      spectrum: 0.2,
    ),
  ),
  EffectPreset(
    'SOLAR FLARE',
    EffectParams(
      kind: EffectKind.sparks,
      intensity: 0.9,
      speed: 1.2,
      density: 0.75,
      spectrum: 0.7,
      bloom: 0.85,
    ),
  ),
  EffectPreset(
    'VAPOURWAVE',
    EffectParams(
      kind: EffectKind.chromaflow,
      intensity: 0.8,
      speed: 0.5,
      density: 0.7,
      spectrum: 0.85,
      bloom: 0.65,
      grain: 0.1,
    ),
  ),
  EffectPreset(
    'NONE',
    EffectParams(kind: EffectKind.none, intensity: 0.0),
  ),
];

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
    this.spectrum = 0.6,
    this.saturation = 0.85,
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

  /// 0..1 — how far the effect drifts off the phosphor palette into a full
  /// hue ramp. 0 keeps everything monochrome (pure terminal), 1 is full
  /// colour. This is what makes the effect section genuinely colourful.
  final double spectrum;

  /// 0..1 — colour vividness once [spectrum] has taken effect.
  final double saturation;

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
    double? spectrum,
    double? saturation,
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
      spectrum: spectrum ?? this.spectrum,
      saturation: saturation ?? this.saturation,
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
        'spectrum': spectrum,
        'saturation': saturation,
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
      spectrum: (j['spectrum'] as num?)?.toDouble() ?? 0.25,
      saturation: (j['saturation'] as num?)?.toDouble() ?? 0.7,
    );
  }

  /// Index into [EffectKind.values] — used for stable ordering in the browser.
  int get ordinal => kind.index;

  static const Map<EffectKind, String> labels = {
    // phosphor
    EffectKind.matrix: 'MATRIX',
    EffectKind.glyphrain: 'GLYPH',
    EffectKind.neonrain: 'NEON',
    EffectKind.circuit: 'CIRCUIT',
    // fields
    EffectKind.plasma: 'PLASMA',
    EffectKind.diffusion: 'DIFFUSION',
    EffectKind.chromaflow: 'CHROMA',
    EffectKind.aurora: 'AURORA',
    EffectKind.bloomfield: 'BLOOM',
    // geometry
    EffectKind.wireframe: 'WIREFRAME',
    EffectKind.gridwarp: 'GRIDWARP',
    EffectKind.tunnel: 'TUNNEL',
    EffectKind.kaleido: 'KALEIDO',
    // particles
    EffectKind.starfield: 'STARFIELD',
    EffectKind.wormhole: 'WORMHOLE',
    EffectKind.sparks: 'SPARKS',
    EffectKind.metaballs: 'METABALLS',
    // signal
    EffectKind.ripple: 'RIPPLE',
    EffectKind.radar: 'RADAR',
    EffectKind.lissajous: 'LISSAJOUS',
    EffectKind.voronoi: 'VORONOI',
    // text
    EffectKind.asciiwave: 'ASCIIWAVE',
    EffectKind.dither: 'DITHER',
    EffectKind.spectrum: 'SPECTRUM',
    EffectKind.hologram: 'HOLOGRAM',
    EffectKind.layers: 'LAYERS',
    EffectKind.none: 'NONE',
  };

  static const Map<EffectKind, String> descriptions = {
    EffectKind.matrix: 'Falling glyph rain. The canonical terminal effect.',
    EffectKind.glyphrain: 'Falling ASCII glyphs in a slow, quiet rain.',
    EffectKind.neonrain: 'Glyph rain with a wet neon smear and colour bleed.',
    EffectKind.circuit: 'Traces racing along a hardware lattice.',
    EffectKind.plasma: 'Sinusoidal plasma with chromatic separation.',
    EffectKind.diffusion: 'Slow reaction–diffusion field behind the glass.',
    EffectKind.chromaflow: 'Liquid colour bands warping into each other.',
    EffectKind.aurora: 'Layered curtains of drifting colour.',
    EffectKind.bloomfield: 'Soft drifting light blooms that breathe.',
    EffectKind.wireframe: 'Terrain mesh scroll, horizon perspective.',
    EffectKind.gridwarp: 'Perspective grid bending into a gravity well.',
    EffectKind.tunnel: 'Endless tunnel of coloured rings rushing past.',
    EffectKind.kaleido: 'Six-fold mirrored lattice, rotating slowly.',
    EffectKind.starfield: 'Hyperspace streak field, depth-sorted.',
    EffectKind.wormhole: 'Vortex of dust spiralling into the centre.',
    EffectKind.sparks: 'Embers lifting on a heat plume.',
    EffectKind.metaballs: 'Merging plasma blobs with a wet specular edge.',
    EffectKind.ripple: 'Concentric interference rings from moving centres.',
    EffectKind.radar: 'Sweeping beam with phosphor afterglow.',
    EffectKind.lissajous: 'Interfering sine curves traced in the dark.',
    EffectKind.voronoi: 'Living cells that jitter and re-tessellate.',
    EffectKind.asciiwave: 'A standing wave rendered entirely in characters.',
    EffectKind.dither: 'Ordered-dither gradient — old print, new pixels.',
    EffectKind.spectrum: 'Full-hue noise field, like a broken test card.',
    EffectKind.hologram: 'Scanline interference with chromatic fringe.',
    EffectKind.layers: 'Random parallax layers, drifting and re-seeding.',
    EffectKind.none: 'Nothing. Just the starfield.',
  };
}

/// Colour ramp helper.
///
/// Every painter asks this for its colour instead of hardcoding palette
/// entries, so the single `spectrum` slider recolours the entire catalogue.
/// At `spectrum == 0` it returns the phosphor palette exactly; as it rises the
/// hue walks around the wheel and saturation opens up.
class EffectPalette {
  EffectPalette(this.palette, this.params);

  final Palette palette;
  final EffectParams params;

  /// Map a palette colour into the ramped colour space.
  Color ramp(Color base, {double shift = 0.0, double? sat, double? light}) {
    if (params.spectrum <= 0.001) return base;

    final hsl = HSLColor.fromColor(base);
    // Palette colours are all near-monochrome phosphor; give them the
    // palette's own hue as the anchor so the ramp stays on-brand.
    final anchor = hsl.hue / 360.0;
    final h = (anchor * (1 - params.spectrum) +
            (params.hue + shift) * params.spectrum) %
        1.0;

    final s = ((sat ?? hsl.saturation) * 0.25 +
            params.saturation * params.spectrum * 0.85)
        .clamp(0.0, 1.0);
    final l = (light ?? hsl.lightness).clamp(0.0, 1.0);

    return HSLColor.fromAHSL(hsl.alpha, h * 360.0, s, l).toColor();
  }

  /// A direct hue sample — used by effects that want an explicit rainbow.
  Color hue(double t, {double light = 0.55, double alpha = 1.0}) {
    final h = (t + params.hue) % 1.0;
    final s = (0.25 + params.saturation * 0.75).clamp(0.0, 1.0);
    // Blend toward the palette so a low spectrum still reads as terminal.
    final pure = HSLColor.fromAHSL(alpha, h * 360.0, s, light).toColor();
    return Color.lerp(palette.mid.withValues(alpha: alpha), pure,
        params.spectrum.clamp(0.0, 1.0))!
        .withValues(alpha: alpha);
  }
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
    _c = EffectPalette(palette, params);

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
      case EffectKind.circuit:
        _paintCircuit(canvas, size, t);
      case EffectKind.bloomfield:
        _paintBloomfield(canvas, size, t);
      case EffectKind.glyphrain:
        _paintGlyphRain(canvas, size, t);
      case EffectKind.neonrain:
        _paintNeonRain(canvas, size, t);
      case EffectKind.chromaflow:
        _paintChromaFlow(canvas, size, t);
      case EffectKind.tunnel:
        _paintTunnel(canvas, size, t);
      case EffectKind.kaleido:
        _paintKaleido(canvas, size, t);
      case EffectKind.wormhole:
        _paintWormhole(canvas, size, t);
      case EffectKind.sparks:
        _paintSparks(canvas, size, t);
      case EffectKind.metaballs:
        _paintMetaballs(canvas, size, t);
      case EffectKind.radar:
        _paintRadar(canvas, size, t);
      case EffectKind.lissajous:
        _paintLissajous(canvas, size, t);
      case EffectKind.voronoi:
        _paintVoronoi(canvas, size, t);
      case EffectKind.asciiwave:
        _paintAsciiWave(canvas, size, t);
      case EffectKind.dither:
        _paintDither(canvas, size, t);
      case EffectKind.spectrum:
        _paintSpectrum(canvas, size, t);
      case EffectKind.hologram:
        _paintHologram(canvas, size, t);
      case EffectKind.none:
        break;
    }

    if (params.grain > 0.01) _paintGrain(canvas, size, t);
  }

  /// Rebuilt once per frame; cheap because it holds nothing but two refs.
  late EffectPalette _c;

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
        trail.color = _c
            .ramp(i == 0 ? palette.bright : palette.mid, shift: i * 0.012)
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
        final base = _c
            .ramp(palette.mid, shift: n * 0.30)
            .withValues(alpha: alpha);
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
              ..color = _c
                  .ramp(palette.bright, shift: 0.5)
                  .withValues(alpha: alpha * 0.30)
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

      paint.color = _c.ramp(palette.bright, shift: angle / 6.283).withValues(alpha: alpha);
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
      final tint = _c.ramp(
        Color.lerp(palette.mid, palette.bright, baseHue)!,
        shift: baseHue * 0.6,
      );
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


  /// Traces racing along a lattice, like signal on a circuit board.
  void _paintCircuit(Canvas canvas, Size size, double t) {
    final rnd = math.Random(9137);
    final step = 22.0 + (1 - params.density) * 26;
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;

    // Static lattice.
    paint.color = palette.line.withValues(alpha: 0.30 * params.intensity);
    for (var i = 0; i < cols; i++) {
      final x = i * step;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var j = 0; j < rows; j++) {
      final y = j * step;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Pulses travelling along a row or column.
    final n = (18 + params.density * 40).round();
    for (var k = 0; k < n; k++) {
      final horizontal = rnd.nextBool();
      final lane = (horizontal ? rows : cols) * rnd.nextDouble();
      final phase = (t * (0.15 + rnd.nextDouble() * 0.5) + rnd.nextDouble()) % 1;
      final len = 0.06 + rnd.nextDouble() * 0.16;
      final a = phase * (horizontal ? size.width : size.height);
      final b = math.min(
        (phase + len) * (horizontal ? size.width : size.height),
        horizontal ? size.width : size.height,
      );
      final c = _c
          .ramp(palette.bright, shift: rnd.nextDouble() * 0.5)
          .withValues(alpha: 0.55 * params.intensity);
      paint
        ..color = c
        ..strokeWidth = 1.2;
      if (horizontal) {
        canvas.drawLine(Offset(a, lane * step), Offset(b, lane * step), paint);
      } else {
        canvas.drawLine(Offset(lane * step, a), Offset(lane * step, b), paint);
      }
    }
  }

  /// Slow, breathing light blooms that drift and overlap.
  void _paintBloomfield(Canvas canvas, Size size, double t) {
    final rnd = math.Random(9137);
    final n = (4 + params.density * 7).round();
    for (var i = 0; i < n; i++) {
      final cx = rnd.nextDouble() * size.width;
      final cy = rnd.nextDouble() * size.height;
      final drift = 0.35 + rnd.nextDouble() * 0.9;
      final x = cx + math.sin(t * drift + i) * size.width * 0.12;
      final y = cy + math.cos(t * drift * 0.8 + i) * size.height * 0.10;
      final r = (size.shortestSide * (0.10 + rnd.nextDouble() * 0.22)) *
          (0.75 + 0.25 * math.sin(t * 0.5 + i));
      final base = _c.hue(
        rnd.nextDouble() * 0.25,
        light: (0.32 + 0.22 * params.bloom).clamp(0.2, 0.72),
      );
      final paint = Paint()
        ..color = base.withValues(alpha: 0.13 * params.intensity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          26 + 34 * params.bloom,
        );
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  /// Falling ASCII glyphs — a slower, textual cousin of the matrix rain.
  static const List<String> _glyphs = [
    '·', '+', '*', '░', '▒', '≈', '≡', '∷', '∎', '◇', '△', '⌁', '•', '∘',
  ];

  void _paintGlyphRain(Canvas canvas, Size size, double t) {
    final rnd = math.Random(9137);
    final colW = 16.0 + (1 - params.density) * 14;
    final cols = (size.width / colW).ceil();
    for (var i = 0; i < cols; i++) {
      final x = i * colW + colW * 0.5;
      final speed = 0.25 + rnd.nextDouble() * 0.9;
      final offset = rnd.nextDouble();
      final headY = ((t * speed + offset) % 1.3 - 0.15) * size.height;
      final tail = 60 + rnd.nextDouble() * 180;
      for (var k = 0; k < 9; k++) {
        final y = headY - k * (tail / 9);
        if (y < -20 || y > size.height + 20) continue;
        final fade = (1 - k / 9) * params.intensity;
        final g = _glyphs[rnd.nextInt(_glyphs.length)];
        final tp = TextPainter(
          text: TextSpan(
            text: g,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 11,
              color: _c
                  .ramp(k == 0 ? palette.bright : palette.ok, shift: k * 0.03)
                  .withValues(alpha: 0.55 * fade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // New renderers
  // ══════════════════════════════════════════════════════════════════════

  /// Wet neon smear: glyph columns with a blurred colour copy underneath.
  void _paintNeonRain(Canvas canvas, Size size, double t) {
    final rnd = math.Random(4711);
    final colW = 13.0 + (1 - params.density) * 16;
    final cols = (size.width / colW).ceil();
    final rect = Offset.zero & size;

    canvas.saveLayer(
      rect,
      Paint()..blendMode = BlendMode.plus,
    );
    for (var i = 0; i < cols; i++) {
      final x = i * colW + colW * 0.5;
      final speed = 0.18 + rnd.nextDouble() * 0.75;
      final phase = rnd.nextDouble();
      final tail = 90 + rnd.nextDouble() * 240;
      final hueOff = rnd.nextDouble();

      // The glow pass: one wide blurred stroke down the column.
      final headY = ((t * speed + phase) % 1.4 - 0.2) * size.height;
      final glowPaint = Paint()
        ..strokeWidth = colW * 0.85
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 10 * params.bloom)
        ..color = _c
            .hue(hueOff, light: 0.5)
            .withValues(alpha: 0.16 * params.intensity);
      canvas.drawLine(
        Offset(x, headY - tail),
        Offset(x, headY),
        glowPaint,
      );

      // The crisp glyph pass on top.
      for (var k = 0; k < 11; k++) {
        final y = headY - k * (tail / 11);
        if (y < -20 || y > size.height + 20) continue;
        final fade = (1 - k / 11) * params.intensity;
        final g = _glyphs[rnd.nextInt(_glyphs.length)];
        final tp = TextPainter(
          text: TextSpan(
            text: g,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10,
              fontWeight: k == 0 ? FontWeight.w700 : FontWeight.w400,
              color: _c.hue(
                hueOff + k * 0.02,
                light: k == 0 ? 0.86 : 0.66,
                alpha: (0.85 * fade).clamp(0.0, 1.0),
              ),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y));
      }
    }
    canvas.restore();
  }

  /// Liquid colour bands that warp through each other like ink in water.
  void _paintChromaFlow(Canvas canvas, Size size, double t) {
    final rect = Offset.zero & size;
    final bands = (4 + params.density * 8).round();
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);

    for (var b = 0; b < bands; b++) {
      final f = b / bands;
      final phase = t * math.pi * 2 * (0.08 + f * 0.10) + f * 5.1;
      final yBase = size.height * (0.1 + f * 0.85);
      final amp = size.height * (0.05 + params.warp * 0.16);

      final path = Path();
      const steps = 26;
      for (var i = 0; i <= steps; i++) {
        final g = i / steps;
        final x = g * size.width;
        final y = yBase +
            math.sin(g * 5.2 * params.scale + phase) * amp +
            math.sin(g * 11.7 * params.scale - phase * 1.7) * amp * 0.35;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (var i = steps; i >= 0; i--) {
        final g = i / steps;
        final x = g * size.width;
        final y = yBase +
            math.sin(g * 5.2 * params.scale + phase) * amp +
            math.sin(g * 11.7 * params.scale - phase * 1.7) * amp * 0.35 +
            (14 + 26 * params.warp);
        path.lineTo(x, y);
      }
      path.close();

      final tint = _c.hue(f * 0.9, light: 0.55);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: 0.0),
              tint.withValues(alpha: 0.20 * params.intensity),
              tint.withValues(alpha: 0.05 * params.intensity),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  /// Endless tunnel: concentric rings that grow toward the viewer, each one
  /// hue-shifted so the walls read as a coloured corridor.
  void _paintTunnel(Canvas canvas, Size size, double t) {
    final cx = size.width * 0.5 +
        math.sin(t * 0.4) * size.width * 0.06 * params.warp;
    final cy = size.height * 0.5 +
        math.cos(t * 0.31) * size.height * 0.05 * params.warp;
    final maxR = math.sqrt(size.width * size.width +
            size.height * size.height) *
        0.62;

    final rings = (14 + params.density * 26).round();
    final paint = Paint()
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < rings; i++) {
      // z walks 0..1 and wraps, so rings fly outward.
      final z = ((i / rings) + t * 0.28) % 1.0;
      final r = 2 + math.pow(z, 2.0) * maxR;
      final fade = 1.0 - z;
      final alpha = (fade * params.intensity * 0.85).clamp(0.0, 1.0);
      if (alpha < 0.02) continue;

      paint
        ..strokeWidth = 0.7 + z * 2.4
        ..color = _c
            .hue(i / rings, light: 0.6)
            .withValues(alpha: alpha * 0.8);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    // Radial spokes give the corridor its walls.
    const spokes = 14;
    final spokePaint = Paint()..strokeWidth = 0.9;
    for (var s = 0; s < spokes; s++) {
      final a = (s / spokes) * math.pi * 2 + t * 0.22;
      spokePaint.color = _c
          .hue(s / spokes, light: 0.5)
          .withValues(alpha: 0.20 * params.intensity);
      canvas.drawLine(
        Offset(cx + math.cos(a) * maxR, cy + math.sin(a) * maxR),
        Offset(cx + math.cos(a) * 6, cy + math.sin(a) * 6),
        spokePaint,
      );
    }

    // A bright aperture at the vanishing point.
    canvas.drawCircle(
      Offset(cx, cy),
      3 + params.bloom * 18,
      Paint()
        ..color = _c
            .hue(0, light: 0.85)
            .withValues(alpha: 0.35 * params.intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  /// N-fold mirrored lattice — cheap to draw, reads as stained glass.
  void _paintKaleido(Canvas canvas, Size size, double t) {
    const folds = 6;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rMax = math.sqrt(cx * cx + cy * cy);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final layers = (3 + params.density * 6).round();
    for (var l = 0; l < layers; l++) {
      final lf = l / layers;
      final wobble = math.sin(t * 0.5 + l * 1.7) * 0.18 * params.warp;
      final tint = _c.hue(lf * 0.8, light: 0.6);
      paint.color = tint.withValues(alpha: 0.34 * params.intensity);

      final path = Path();
      const segs = 220;
      for (var i = 0; i <= segs; i++) {
        final th = (i / segs) * math.pi * 2;
        final folded = th * folds / (math.pi * 2);
        final rf = (0.30 + lf * 0.6 + wobble) *
            rMax *
            (0.55 + 0.45 * math.sin(folded * 3.1 * params.scale + t * 0.6));
        final x = cx + math.cos(th) * rf;
        final y = cy + math.sin(th) * rf;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);

      // Radial seam lines.
      for (var f = 0; f < folds * 2; f++) {
        final a = (f / (folds * 2)) * math.pi * 2 + t * 0.05;
        paint.color = tint.withValues(alpha: 0.12 * params.intensity);
        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + math.cos(a) * rMax, cy + math.sin(a) * rMax),
          paint,
        );
      }
    }
  }

  /// Dust spiralling into a bright core, with streak trails.
  void _paintWormhole(Canvas canvas, Size size, double t) {
    final rnd = math.Random(8801);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.sqrt(cx * cx + cy * cy);
    final n = (60 + params.density * 300).round();
    final paint = Paint()..strokeWidth = 1.2;

    for (var i = 0; i < n; i++) {
      final arm = rnd.nextDouble();
      final offset = rnd.nextDouble();
      final spin = 0.5 + rnd.nextDouble() * 1.4;
      final bright = 0.3 + rnd.nextDouble() * 0.7;

      // Radius shrinks over time — the particle falls inward.
      final z = ((offset + t * (0.10 + arm * 0.25) * spin) % 1.0);
      final r = (1.0 - z) * maxR;
      if (r < 3) continue;

      // Angular position tightens as it falls (conservation of angular
      // momentum, faked): outer particles lag, inner ones whip round.
      final theta = arm * math.pi * 2 +
          t * 1.1 * params.speed +
          (1.0 - z) * 3.4 * (0.5 + params.warp);

      final x = cx + math.cos(theta) * r;
      final y = cy + math.sin(theta) * r * 0.92;
      final alpha = (bright * params.intensity * (0.25 + z * 0.75))
          .clamp(0.0, 1.0);
      if (alpha < 0.03) continue;

      // Trail: a short arc backwards along the orbit.
      final tl = 0.06 + z * 0.14;
      final x2 = cx + math.cos(theta - tl) * (r + 2);
      final y2 = cy + math.sin(theta - tl) * (r + 2) * 0.92;

      paint.color = _c
          .hue(arm * 0.7 + z * 0.3, light: 0.72)
          .withValues(alpha: alpha * 0.8);
      canvas.drawLine(Offset(x, y), Offset(x2, y2), paint);
    }

    // Core.
    final coreR = 8 + params.bloom * 26;
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()
        ..color = _c.hue(0, light: 0.9).withValues(alpha: 0.45 * params.intensity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + params.bloom * 18),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      coreR * 0.25,
      Paint()..color = _c.hue(0, light: 0.97).withValues(alpha: 0.9),
    );
  }

  /// Embers rising on a heat plume.
  void _paintSparks(Canvas canvas, Size size, double t) {
    final rnd = math.Random(3319);
    final n = (30 + params.density * 160).round();
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < n; i++) {
      final xBase = rnd.nextDouble() * size.width;
      final rise = 0.15 + rnd.nextDouble() * 0.85;
      final phase = rnd.nextDouble();
      final drift = (rnd.nextDouble() - 0.5) * size.width * 0.22;
      final size0 = 0.8 + rnd.nextDouble() * 2.2;

      final p = (phase + t * rise) % 1.0;
      final y = size.height * (1.05 - p * 1.15);
      final sway = math.sin(p * 6.2 + phase * 9) * 14;
      final x = xBase + drift * p + sway;

      // Fade in at the bottom, out at the top.
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0);
      final alpha = (fade * params.intensity * 0.9).clamp(0.0, 1.0);
      if (alpha < 0.03) continue;

      paint
        ..strokeWidth = size0
        ..color = _c
            .hue(phase * 0.6, light: 0.55 + fade * 0.4)
            .withValues(alpha: alpha);
      // Ember streak.
      canvas.drawLine(
        Offset(x, y),
        Offset(x - sway * 0.02, y + 5 + size0 * 5),
        paint,
      );

      if (params.bloom > 0.2 && size0 > 2.4) {
        canvas.drawCircle(
          Offset(x, y),
          size0 * 3,
          Paint()
            ..color = paint.color.withValues(alpha: alpha * 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }
  }

  /// Merging plasma blobs. Uses additive layer compositing so overlaps blow
  /// out to white in the middle — the classic "wet blob" look.
  void _paintMetaballs(Canvas canvas, Size size, double t) {
    final rnd = math.Random(6023);
    final n = (5 + params.density * 12).round();
    final rect = Offset.zero & size;

    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
    for (var i = 0; i < n; i++) {
      final ax = rnd.nextDouble() * size.width;
      final ay = rnd.nextDouble() * size.height;
      final fx = 0.25 + rnd.nextDouble() * 0.9;
      final fy = 0.25 + rnd.nextDouble() * 0.9;
      final ph = rnd.nextDouble() * math.pi * 2;

      final x = ax + math.sin(t * fx + ph) * size.width * 0.20;
      final y = ay + math.cos(t * fy + ph * 1.3) * size.height * 0.18;
      final r = size.shortestSide * (0.13 + rnd.nextDouble() * 0.20) *
          (0.8 + 0.3 * math.sin(t * 0.8 + ph));

      final tint = _c.hue(rnd.nextDouble() * 0.8, light: 0.5);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = tint.withValues(alpha: 0.30 * params.intensity)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            r * (0.35 + params.bloom * 0.4),
          ),
      );
    }
    canvas.restore();

    // Specular rim: a second pass with stroked circles at low alpha.
    for (var i = 0; i < n; i++) {
      final x = size.width * rnd.nextDouble();
      final y = size.height * rnd.nextDouble();
      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()
          ..color = _c.hue(rnd.nextDouble(), light: 0.95)
              .withValues(alpha: 0.35 * params.intensity),
      );
    }
  }

  /// Sweeping radar beam with a phosphor afterglow wedge.
  void _paintRadar(Canvas canvas, Size size, double t) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rMax = math.min(size.width, size.height) * 0.44;
    final sweep = t * math.pi * 2 * 0.28;

    // Grid: range rings + crosshair.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _c.ramp(palette.line).withValues(alpha: 0.55);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(Offset(cx, cy), rMax * i / 4, grid);
    }
    canvas.drawLine(Offset(cx - rMax, cy), Offset(cx + rMax, cy), grid);
    canvas.drawLine(Offset(cx, cy - rMax), Offset(cx, cy + rMax), grid);

    // Afterglow wedge: several trailing sectors at decreasing alpha.
    const trail = 26;
    for (var i = trail; i >= 0; i--) {
      final a = sweep - i * 0.035;
      final alpha =
          (1 - i / trail) * 0.20 * params.intensity * (i == 0 ? 3.0 : 1.0);
      final path = Path()
        ..moveTo(cx, cy)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: rMax),
          a - 0.02,
          0.04,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = _c
              .hue(0.33, light: 0.6)
              .withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }

    // Beam line.
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + math.cos(sweep) * rMax, cy + math.sin(sweep) * rMax),
      Paint()
        ..strokeWidth = 1.6
        ..color = _c.hue(0.33, light: 0.9).withValues(alpha: 0.85),
    );

    // Contacts that only light up when the beam passes over them.
    final rnd = math.Random(1177);
    for (var i = 0; i < (6 + params.density * 14).round(); i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final r = rMax * (0.2 + rnd.nextDouble() * 0.78);
      final delta = ((sweep - a) % (math.pi * 2) + math.pi * 2) %
          (math.pi * 2);
      final hot = (1 - delta / (math.pi * 2)).clamp(0.0, 1.0);
      final alpha = (0.15 + math.pow(hot, 6).toDouble() * 0.85) *
          params.intensity;
      canvas.drawCircle(
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        1.6 + hot * 2.4,
        Paint()
          ..color = _c.hue(0.33, light: 0.8).withValues(alpha: alpha)
          ..maskFilter = hot > 0.5
              ? const MaskFilter.blur(BlurStyle.normal, 4)
              : null,
      );
    }
  }

  /// Interfering Lissajous curves — a plotter drawing in the dark.
  void _paintLissajous(Canvas canvas, Size size, double t) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final ax = size.width * 0.42;
    final ay = size.height * 0.42;
    final curves = (3 + params.density * 7).round();

    for (var c = 0; c < curves; c++) {
      final f = c / curves;
      final a = 2 + f * 5;
      final b = 3 + f * 4;
      final delta = t * math.pi * 2 * (0.15 + f * 0.25) + f * 2.4;

      final path = Path();
      const steps = 520;
      for (var i = 0; i <= steps; i++) {
        final th = (i / steps) * math.pi * 2;
        final x = cx + math.sin(a * th + delta) * ax * (0.55 + f * 0.45);
        final y = cy + math.sin(b * th) * ay * (0.55 + f * 0.45);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9 + params.bloom
          ..color = _c
              .hue(f * 0.85, light: 0.65)
              .withValues(alpha: 0.45 * params.intensity),
      );
    }
  }

  /// Jittering Voronoi cells, drawn as their edge set.
  void _paintVoronoi(Canvas canvas, Size size, double t) {
    final rnd = math.Random(2591);
    // Fewer seeds than you might expect: the cell edges are what read.
    final n = (9 + params.density * 26).round();
    final seeds = <Offset>[];
    final drifts = <Offset>[];
    for (var i = 0; i < n; i++) {
      seeds.add(Offset(rnd.nextDouble() * size.width,
          rnd.nextDouble() * size.height));
      drifts.add(Offset(
        (rnd.nextDouble() - 0.5) * 1.4,
        (rnd.nextDouble() - 0.5) * 1.4,
      ));
    }

    // Move seeds on slow orbits.
    final live = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          seeds[i].dx + math.sin(t * drifts[i].dx + i) * size.width * 0.07,
          seeds[i].dy + math.cos(t * drifts[i].dy + i) * size.height * 0.07,
        ),
    ];

    // For each seed, the perpendicular bisector half-plane against every
    // other seed becomes a polygon we can clip to.
    final cellPaint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      final self = live[i];
      var path = Path()..addRect(Offset.zero & size);
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final other = live[j];
        final mx = (self.dx + other.dx) / 2;
        final my = (self.dy + other.dy) / 2;
        final nx = other.dx - self.dx;
        final ny = other.dy - self.dy;
        final len = math.sqrt(nx * nx + ny * ny);
        if (len < 1) continue;
        // Clip to the half-plane keeping the self side.
        final big = size.width + size.height;
        final px = -ny / len * big;
        final py = nx / len * big;
        final clip = Path()
          ..moveTo(mx + px, my + py)
          ..lineTo(mx - px, my - py)
          ..lineTo(mx - px - nx * 2, my - py - ny * 2)
          ..lineTo(mx + px - nx * 2, my + py - ny * 2)
          ..close();
        path = Path.combine(PathOperation.intersect, path, clip);
      }
      cellPaint.color = _c
          .hue(i / n, light: 0.6)
          .withValues(alpha: 0.22 * params.intensity);
      canvas.drawPath(path, cellPaint);
    }

    // Seed points.
    for (final s in live) {
      canvas.drawCircle(
        s,
        1.4,
        Paint()
          ..color = _c.hue(0, light: 0.92).withValues(alpha: 0.6 * params.intensity),
      );
    }
  }

  /// A standing wave rendered entirely in ASCII.
  void _paintAsciiWave(Canvas canvas, Size size, double t) {
    const ramp = ' .:-=+*#%@';
    final cellW = 7.0 + (1 - params.density) * 7;
    final cellH = 11.0;
    final cols = (size.width / cellW).floor();
    final rows = (size.height / cellH).floor();
    if (cols < 2 || rows < 2) return;

    final buf = StringBuffer();
    // Paint row by row so each TextPainter draws a whole line: one layout
    // call per row instead of one per glyph.
    for (var r = 0; r < rows; r++) {
      buf.clear();
      final ny = r / rows;
      for (var c = 0; c < cols; c++) {
        final nx = c / cols;
        final v = math.sin(nx * 7 * params.scale + t * math.pi * 2) +
            math.sin(ny * 5 * params.scale - t * math.pi * 1.6) +
            math.sin((nx + ny) * 4 * params.scale + t);
        final norm = ((v + 3) / 6).clamp(0.0, 1.0);
        final idx = (norm * (ramp.length - 1)).round();
        buf.write(ramp[idx]);
      }
      final text = buf.toString();
      if (text.trim().isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: cellH * 0.92,
            height: 1.0,
            letterSpacing: cellW - cellH * 0.60,
            color: _c
                .hue(ny * 0.7 + t * 0.05, light: 0.55)
                .withValues(alpha: 0.55 * params.intensity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, r * cellH));
    }
  }

  /// Ordered (Bayer) dither gradient — 4×4 matrix, drawn as one rect per cell.
  static const List<List<int>> _bayer = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ];

  void _paintDither(Canvas canvas, Size size, double t) {
    final cell = 4.0 + (1 - params.density) * 6;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final paint = Paint();

    for (var r = 0; r < rows; r++) {
      final ny = r / rows;
      for (var c = 0; c < cols; c++) {
        final nx = c / cols;
        // Source luminance: a drifting interference pattern.
        final lum = 0.5 +
            0.5 *
                math.sin(nx * 9 * params.scale + t * 3.1) *
                math.cos(ny * 7 * params.scale - t * 2.4);
        final threshold = (_bayer[r % 4][c % 4] + 0.5) / 16.0;
        if (lum < threshold) continue;
        paint.color = _c
            .hue(nx * 0.8 + ny * 0.35, light: 0.55 + lum * 0.3)
            .withValues(alpha: 0.45 * params.intensity);
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4),
          paint,
        );
      }
    }
  }

  /// Full-hue noise field — a broken test card.
  void _paintSpectrum(Canvas canvas, Size size, double t) {
    // Wide bars whose hue walks, plus a moving scanline highlight.
    final bars = (10 + params.density * 26).round();
    final bw = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final f = i / bars;
      final wob = 0.5 + 0.5 * math.sin(f * 8.0 + t * math.pi * 2);
      canvas.drawRect(
        Rect.fromLTWH(i * bw, 0, bw + 0.4, size.height),
        Paint()
          ..color = _c
              .hue(f + t * 0.1, light: 0.30 + wob * 0.28)
              .withValues(alpha: (0.12 + wob * 0.30) * params.intensity),
      );
    }
    // Horizontal interference bands.
    final bands = (24 + params.density * 40).round();
    final bh = size.height / bands;
    for (var j = 0; j < bands; j++) {
      final f = j / bands;
      final wob = 0.5 + 0.5 * math.cos(f * 14.0 - t * math.pi * 2.6);
      canvas.drawRect(
        Rect.fromLTWH(0, j * bh, size.width, bh * 0.55),
        Paint()
          ..color = _c
              .hue(1 - f + t * 0.12, light: 0.5)
              .withValues(alpha: wob * 0.18 * params.intensity)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  /// Hologram: fine scanlines with a chromatic fringe and a rolling tear.
  void _paintHologram(Canvas canvas, Size size, double t) {
    // Interference lines.
    final linePaint = Paint()..strokeWidth = 1;
    final gap = 2.0 + (1 - params.density) * 4;
    for (var y = 0.0; y < size.height; y += gap) {
      final f = y / size.height;
      final shimmer =
          0.5 + 0.5 * math.sin(f * 30 + t * math.pi * 2 * 1.7);
      linePaint.color = _c
          .hue(f * 0.6 + t * 0.06, light: 0.6)
          .withValues(alpha: (0.08 + shimmer * 0.14) * params.intensity);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Chromatic fringe: two offset copies of a soft vertical band.
    final bandY = ((t * 0.55) % 1.4 - 0.2) * size.height;
    for (var k = 0; k < 3; k++) {
      final off = (k - 1) * (2.0 + params.chroma * 10);
      canvas.drawRect(
        Rect.fromLTWH(off, bandY - 26, size.width, 52),
        Paint()
          ..color = _c
              .hue(k * 0.33, light: 0.6)
              .withValues(alpha: 0.12 * params.intensity)
          ..blendMode = BlendMode.plus,
      );
    }

    // Rolling tear.
    final tearY = ((t * 0.22 + 0.4) % 1.0) * size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, tearY, size.width, 3),
      Paint()..color = _c.hue(0.5, light: 0.9).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) =>
      old.palette != palette ||
      old.params != params ||
      old.ticker != ticker;
}
