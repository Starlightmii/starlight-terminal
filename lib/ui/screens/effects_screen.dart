import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/effects.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// Live effect stack: pick a background renderer and tune it in real time.
class EffectsScreen extends StatelessWidget {
  const EffectsScreen({super.key});

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
            trailing: Text(
              EffectParams.labels[fx.kind] ?? '—',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: palette.bright,
              ),
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
                      child: Text(
                        '≫ preview surface\n'
                        '${EffectParams.descriptions[fx.kind] ?? ''}',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 9.5,
                          height: 1.5,
                          color: palette.mid,
                        ),
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
          flex: 4,
          child: TermPanel(
            palette: palette,
            title: 'RENDERER',
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in EffectKind.values)
                            _kindChip(studio, palette, k, fx.kind == k),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                      _slider(
                        palette,
                        'chroma',
                        fx.chroma,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(chroma: v)),
                      ),
                      _slider(
                        palette,
                        'grain',
                        fx.grain,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(grain: v)),
                      ),
                      _slider(
                        palette,
                        'hue',
                        fx.hue,
                        0,
                        1,
                        (v) => studio.setEffects(fx.copyWith(hue: v)),
                      ),
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
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _button(palette, 'RANDOMISE', studio.randomiseEffects),
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

  Widget _slider(
    Palette palette,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                color: palette.dim,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 1,
                activeTrackColor: palette.mid,
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
