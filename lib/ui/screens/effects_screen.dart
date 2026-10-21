import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/effects.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// Live effect stack: pick a background renderer and tune it in real time.
///
/// The catalogue runs to 27 renderers, so the chips are grouped by family and
/// presets sit above them. Colour is a first-class control here: `spectrum`
/// walks the whole catalogue off the monochrome phosphor ramp and into full
/// hue, and `hue` rotates it once it is there.
class EffectsScreen extends StatefulWidget {
  const EffectsScreen({super.key});

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  EffectFamily? _filter;
  bool _colourOpen = true;

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final fx = studio.effects;

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: TermPanel(
            palette: palette,
            title: 'PREVIEW',
            accent: true,
            padding: EdgeInsets.zero,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _hueStrip(palette, fx),
                const SizedBox(width: 8),
                Text(
                  EffectParams.labels[fx.kind] ?? '—',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: palette.bright,
                  ),
                ),
              ],
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: palette.bg),
                  EffectCanvas(
                    palette: palette,
                    params: fx,
                    animate: !studio.terminal.reduceMotion,
                  ),
                  // A sample of terminal text so the effect can be judged
                  // against real content instead of a bare gradient.
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '≫ ${EffectParams.labels[fx.kind] ?? ''}',
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 10,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: palette.bright,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            EffectParams.descriptions[fx.kind] ?? '',
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 9,
                              height: 1.5,
                              color: palette.mid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 5,
          child: TermPanel(
            palette: palette,
            title: 'RENDERER',
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            trailing: Text(
              '${EffectKind.values.length - 1} effects',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.dim,
              ),
            ),
            child: Column(
              children: [
                // ── presets ─────────────────────────────────────────────
                SizedBox(
                  height: 24,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kEffectPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 5),
                    itemBuilder: (_, i) {
                      final p = kEffectPresets[i];
                      final active = p.params.kind == fx.kind &&
                          (p.params.spectrum - fx.spectrum).abs() < 0.02;
                      return _chip(
                        palette,
                        p.name,
                        active: active,
                        accent: palette.warn,
                        onTap: () => studio.applyPreset(p),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),

                // ── family filter + effect chips ────────────────────────
                SizedBox(
                  height: 22,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip(
                        palette,
                        'ALL',
                        active: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final fam in EffectFamily.values)
                        if (fam != EffectFamily.off) ...[
                          const SizedBox(width: 4),
                          _chip(
                            palette,
                            kEffectFamilyLabel[fam]!,
                            active: _filter == fam,
                            onTap: () => setState(
                              () => _filter = _filter == fam ? null : fam,
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final k in EffectKind.values)
                            if (_filter == null || kEffectFamily[k] == _filter)
                              _kindChip(studio, palette, k, fx.kind == k),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── colour ──────────────────────────────────────
                      _header(palette, 'COLOUR', onTap: () {
                        setState(() => _colourOpen = !_colourOpen);
                      }, open: _colourOpen),
                      if (_colourOpen) ...[
                        _slider(
                          palette,
                          'spectrum',
                          fx.spectrum,
                          0,
                          1,
                          (v) => studio.setEffects(fx.copyWith(spectrum: v)),
                          accent: true,
                        ),
                        _slider(
                          palette,
                          'hue',
                          fx.hue,
                          0,
                          1,
                          (v) => studio.setEffects(fx.copyWith(hue: v)),
                          accent: true,
                        ),
                        _slider(
                          palette,
                          'saturation',
                          fx.saturation,
                          0,
                          1,
                          (v) => studio.setEffects(fx.copyWith(saturation: v)),
                          accent: true,
                        ),
                        _slider(
                          palette,
                          'chroma',
                          fx.chroma,
                          0,
                          1,
                          (v) => studio.setEffects(fx.copyWith(chroma: v)),
                          accent: true,
                        ),
                      ],

                      // ── motion ──────────────────────────────────────
                      _header(palette, 'MOTION'),
                      _slider(
                        palette,
                        'intensity',
                        fx.intensity,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(intensity: v)),
                      ),
                      _slider(
                        palette,
                        'speed',
                        fx.speed,
                        0.1,
                        3,
                        (v) => studio.setEffects(fx.copyWith(speed: v)),
                      ),
                      _slider(
                        palette,
                        'density',
                        fx.density,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(density: v)),
                      ),
                      _slider(
                        palette,
                        'scale',
                        fx.scale,
                        0.4,
                        2.5,
                        (v) => studio.setEffects(fx.copyWith(scale: v)),
                      ),

                      // ── finish ──────────────────────────────────────
                      _header(palette, 'FINISH'),
                      _slider(
                        palette,
                        'bloom',
                        fx.bloom,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(bloom: v)),
                      ),
                      _slider(
                        palette,
                        'warp',
                        fx.warp,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(warp: v)),
                      ),
                      _slider(
                        palette,
                        'grain',
                        fx.grain,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(grain: v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _button(palette, 'RANDOMISE', studio.randomiseEffects),
                    const SizedBox(width: 6),
                    _button(palette, 'SHUFFLE COLOUR', studio.rollColour),
                    const SizedBox(width: 6),
                    _button(palette, 'RESET', studio.resetEffects),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A tiny rainbow strip in the panel header — reads as "this is colourful"
  /// at a glance and doubles as a live hue readout.
  Widget _hueStrip(Palette palette, EffectParams fx) {
    if (fx.spectrum <= 0.02) {
      return Container(
        width: 46,
        height: 8,
        decoration: BoxDecoration(border: Border.all(color: palette.line)),
      );
    }
    return Container(
      width: 46,
      height: 8,
      decoration: BoxDecoration(
        border: Border.all(color: palette.line),
        gradient: LinearGradient(
          colors: [
            for (var i = 0; i <= 5; i++)
              HSLColor.fromAHSL(
                1,
                (((i / 5) + fx.hue) % 1.0) * 360,
                (0.3 + fx.saturation * 0.7).clamp(0.0, 1.0),
                0.55,
              ).toColor(),
          ],
        ),
      ),
    );
  }

  Widget _header(
    Palette palette,
    String label, {
    VoidCallback? onTap,
    bool? open,
  }) {
    final row = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: palette.line),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: palette.dim,
            ),
          ),
          if (open != null) ...[
            const SizedBox(width: 4),
            Text(
              open ? '▾' : '▸',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.dim,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: Container(height: 1, color: palette.line),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _kindChip(
    StudioController studio,
    Palette palette,
    EffectKind k,
    bool active,
  ) {
    return InkWell(
      onTap: () => studio.setEffectKind(k),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? palette.mid.withValues(alpha: 0.18) : null,
          border: Border.all(color: active ? palette.mid : palette.line),
        ),
        child: Text(
          EffectParams.labels[k] ?? k.name,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8.5,
            letterSpacing: 1,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Widget _chip(
    Palette palette,
    String label, {
    required bool active,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final tint = accent ?? palette.mid;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? tint.withValues(alpha: 0.16) : null,
          border: Border.all(
            color: active ? tint : palette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }

  Widget _slider(
    Palette palette,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool accent = false,
  }) {
    final track = accent ? palette.warn : palette.mid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                color: accent ? palette.warn : palette.dim,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 1,
                activeTrackColor: track,
                inactiveTrackColor: palette.line,
                thumbColor: palette.bright,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                color: palette.mid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(Palette palette, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8.5,
            letterSpacing: 1,
            color: palette.mid,
          ),
        ),
      ),
    );
  }
}
