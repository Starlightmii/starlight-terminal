import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// A single background star, computed once at startup.
class _BgStar {
  const _BgStar({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.baseAlpha,
    required this.twinklePhase,
    required this.twinkleSpeed,
  });

  /// Normalised position (0..1).
  final double dx;
  final double dy;
  final double radius;
  final double baseAlpha;
  final double twinklePhase;
  final double twinkleSpeed;
}

/// Animated starfield that sits behind the terminal.
///
/// The star field itself is generated once per size and cached; only the
/// alpha twinkle is recomputed each frame, which keeps it cheap.
class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({
    super.key,
    required this.palette,
    required this.animate,
    this.starCount = 170,
  });

  final Palette palette;
  final bool animate;
  final int starCount;

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  List<_BgStar> _stars = const [];
  Size _generatedFor = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _ticker.repeat();
  }

  @override
  void didUpdateWidget(covariant StarfieldBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_ticker.isAnimating) {
      _ticker.repeat();
    } else if (!widget.animate && _ticker.isAnimating) {
      _ticker.stop();
    }
    if (oldWidget.starCount != widget.starCount) {
      _generatedFor = Size.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureStars(Size size) {
    if (_generatedFor == size && _stars.isNotEmpty) return;
    _generatedFor = size;
    // Deterministic seed: the same sky every launch.
    final rnd = math.Random(1977);
    _stars = List<_BgStar>.generate(widget.starCount, (i) {
      // Bias brightness toward dim stars, like a real sky.
      final r = rnd.nextDouble();
      final bright = r > 0.94
          ? 1.0
          : r > 0.8
          ? 0.62
          : 0.28;
      return _BgStar(
        dx: rnd.nextDouble(),
        dy: rnd.nextDouble(),
        radius: 0.5 + bright * 1.35,
        baseAlpha: 0.18 + bright * 0.55,
        twinklePhase: rnd.nextDouble() * math.pi * 2,
        twinkleSpeed: 0.4 + rnd.nextDouble() * 1.6,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StarfieldPainter(
          palette: widget.palette,
          ticker: widget.animate ? _ticker : null,
          starsProvider: (size) {
            _ensureStars(size);
            return _stars;
          },
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.palette,
    required this.ticker,
    required this.starsProvider,
  }) : super(repaint: ticker);

  final Palette palette;
  final Animation<double>? ticker;
  final List<_BgStar> Function(Size size) starsProvider;

  @override
  void paint(Canvas canvas, Size size) {
    final stars = starsProvider(size);
    final t = ticker?.value ?? 0.0;
    final paint = Paint()..style = PaintingStyle.fill;

    // A soft glow band, like the Milky Way crossing the frame.
    final band = Path()
      ..moveTo(-size.width * 0.2, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.18,
        size.width * 1.2,
        size.height * 0.46,
      )
      ..lineTo(size.width * 1.2, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.58,
        -size.width * 0.2,
        size.height * 1.05,
      )
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.bright.withValues(alpha: 0.035),
            palette.mid.withValues(alpha: 0.012),
            palette.bright.withValues(alpha: 0.03),
          ],
        ).createShader(Offset.zero & size),
    );

    for (final s in stars) {
      final twinkle = ticker == null
          ? 1.0
          : 0.55 +
                0.45 *
                    math.sin(
                      (t * math.pi * 2 * s.twinkleSpeed) + s.twinklePhase,
                    );
      final a = (s.baseAlpha * twinkle).clamp(0.0, 1.0);
      paint.color = palette.bright.withValues(alpha: a);
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        s.radius,
        paint,
      );

      // Bloom on the brightest handful.
      if (s.radius > 1.7) {
        canvas.drawCircle(
          Offset(s.dx * size.width, s.dy * size.height),
          s.radius * 3.2,
          Paint()
            ..color = palette.bright.withValues(alpha: a * 0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.palette != palette || old.ticker != ticker;
}

/// Full-screen CRT treatment: scanlines, phosphor bloom and a vignette.
/// Purely decorative and never intercepts pointer events.
class CrtOverlay extends StatelessWidget {
  const CrtOverlay({
    super.key,
    required this.palette,
    required this.enabled,
    this.scanlineGap = 3.0,
  });

  final Palette palette;
  final bool enabled;
  final double scanlineGap;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const IgnorePointer(child: SizedBox.expand());
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CrtPainter(palette: palette, gap: scanlineGap),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CrtPainter extends CustomPainter {
  _CrtPainter({required this.palette, required this.gap});

  final Palette palette;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    // Scanlines.
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Vignette: darker corners, like a curved tube face.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.82,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.55),
          ],
          stops: const [0.55, 0.82, 1.0],
        ).createShader(rect),
    );

    // Faint phosphor wash so black never reads as pure #000.
    canvas.drawRect(
      rect,
      Paint()..color = palette.bright.withValues(alpha: 0.012),
    );

    // Subtle inner border glow.
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.line.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _CrtPainter old) =>
      old.palette != palette || old.gap != gap;
}

/// The star of the show: a bordered terminal panel with an optional title.
class TermPanel extends StatelessWidget {
  const TermPanel({
    super.key,
    required this.palette,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
    this.accent = false,
  });

  final Palette palette;
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent ? palette.mid : palette.line;
    return Container(
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.72),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: accent
            ? [
                BoxShadow(
                  color: palette.bright.withValues(alpha: 0.07),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) _titleBar(borderColor),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }

  Widget _titleBar(Color borderColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
        color: palette.bg.withValues(alpha: 0.55),
      ),
      child: Row(
        children: [
          Text(
            '[ ${title!} ]',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: palette.mid,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
