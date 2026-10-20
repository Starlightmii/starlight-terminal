import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/effects.dart';
import '../core/palette.dart';
import '../state/studio_controller.dart';
import '../state/terminal_controller.dart';
import 'screens/agents_screen.dart';
import 'screens/boot_screen.dart';
import 'screens/catalogue_screen.dart';
import 'screens/console_screen.dart';
import 'screens/effects_screen.dart';
import 'screens/keys_screen.dart';
import 'screens/log_screen.dart';
import 'screens/sky_map_screen.dart';
import 'widgets/chrome.dart';

/// Root scaffold: effect stack → starfield → chrome → CRT overlay.
class StarlightShell extends StatefulWidget {
  const StarlightShell({super.key});

  @override
  State<StarlightShell> createState() => _StarlightShellState();
}

class _StarlightShellState extends State<StarlightShell> {
  int _tab = _initialTab();
  bool _deepLinkRan = false;

  static const List<String> _tabNames = [
    'console',
    'map',
    'catalogue',
    'agents',
    'keys',
    'effects',
    'log',
    'system',
  ];

  /// Deep-link a view: `?tab=agents`, `?tab=keys`, `?tab=effects`.
  static int _initialTab() {
    final raw = Uri.base.queryParameters['tab']?.toLowerCase();
    if (raw == null) return 0;
    final aliases = <String, String>{
      'catalog': 'catalogue',
      'stars': 'catalogue',
      'notes': 'log',
      'settings': 'system',
      'api': 'keys',
      'apikeys': 'keys',
      'fx': 'effects',
      'shader': 'effects',
      'agent': 'agents',
      'fleet': 'agents',
    };
    final resolved = aliases[raw] ?? raw;
    final i = _tabNames.indexOf(resolved);
    return i < 0 ? 0 : i;
  }

  /// Runs `?cmd=...` once the terminal finishes booting.
  void _maybeRunDeepLink(TerminalController term) {
    if (_deepLinkRan || term.stage != BootStage.ready) return;
    final cmd = Uri.base.queryParameters['cmd'];
    if (cmd == null || cmd.trim().isEmpty) return;
    _deepLinkRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      term.runCommand(cmd);
    });
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final studio = context.watch<StudioController>();
    final palette = term.palette;
    final booting = term.stage == BootStage.booting;
    _maybeRunDeepLink(term);

    final EffectParams fx = studio.effects;
    final effectVisible =
        _tab != 5 && fx.kind != EffectKind.none && !term.reduceMotion;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Effect stack sits below the starfield and is clipped to the frame.
          if (effectVisible)
            Positioned.fill(
              child: Opacity(
                opacity: 0.55 + fx.intensity * 0.45,
                child: EffectCanvas(
                  palette: palette,
                  params: fx,
                  animate: true,
                ),
              ),
            ),

          Positioned.fill(
            child: StarfieldBackground(
              palette: palette,
              animate: !term.reduceMotion,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const TopStatusBar(),
                Expanded(
                  child: booting
                      ? const BootScreen()
                      : Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  0,
                                ),
                                child: _body(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_tab != 7)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: _logTicker(term, palette),
                              ),
                            const SizedBox(height: 6),
                          ],
                        ),
                ),
                if (!booting)
                  TermNavBar(
                    index: _tab,
                    onSelect: (i) => setState(() => _tab = i),
                  ),
              ],
            ),
          ),

          Positioned.fill(
            child: CrtOverlay(palette: palette, enabled: term.crtEnabled),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0:
        return const ConsoleScreen();
      case 1:
        return const SkyMapScreen();
      case 2:
        return const CatalogueScreen();
      case 3:
        return const AgentsScreen();
      case 4:
        return const KeysScreen();
      case 5:
        return const EffectsScreen();
      case 6:
        return const LogScreen();
      case 7:
        return const SystemScreen();
      default:
        return const ConsoleScreen();
    }
  }

  /// One-line ambient ticker above the nav bar.
  Widget _logTicker(TerminalController term, Palette palette) {
    final star = term.brightestVisible;
    final studio = context.watch<StudioController>();
    final agentLine = studio.orchestrating
        ? 'fleet working'
        : '${studio.agents.where((a) => a.enabled).length}/${studio.agents.length} agents';
    final text = star == null
        ? 'no catalogue object above horizon'
        : 'brightest up: ${star.name} '
            '(${star.altitude.toStringAsFixed(0)}° ${star.azimuth.toStringAsFixed(0)}°)';

    return Row(
      children: [
        Text(
          '❯ ',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9,
            color: palette.mid,
          ),
        ),
        Expanded(
          child: Text(
            '$text  ·  LST ${(term.lstDegrees / 15).toStringAsFixed(2)}h  ·  '
            'moon $termGlyph(term)  ·  $agentLine',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9,
              color: palette.dim,
            ),
          ),
        ),
      ],
    );
  }

  String termGlyph(TerminalController t) => t.moonGlyphValue;
}
