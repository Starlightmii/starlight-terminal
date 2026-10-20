import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../state/terminal_controller.dart';
import 'screens/boot_screen.dart';
import 'screens/catalogue_screen.dart';
import 'screens/console_screen.dart';
import 'screens/log_screen.dart';
import 'screens/sky_map_screen.dart';
import '../ui/widgets/chrome.dart';

/// Root scaffold: starfield → chrome → CRT overlay.
class StarlightShell extends StatefulWidget {
  const StarlightShell({super.key});

  @override
  State<StarlightShell> createState() => _StarlightShellState();
}

class _StarlightShellState extends State<StarlightShell> {
  int _tab = _initialTab();
  bool _deepLinkRan = false;

  /// Allows deep-linking a view: `?tab=map`, `?tab=catalogue`, `?tab=log`.
  static int _initialTab() {
    final raw = Uri.base.queryParameters['tab']?.toLowerCase();
    switch (raw) {
      case 'map':
        return 1;
      case 'catalogue':
      case 'catalog':
      case 'stars':
        return 2;
      case 'log':
      case 'notes':
        return 3;
      case 'system':
      case 'settings':
        return 4;
      default:
        return 0;
    }
  }

  /// Runs `?cmd=...` once the terminal finishes booting. Handy for sharing a
  /// link that lands straight on, say, a star data sheet.
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
    final palette = term.palette;
    final booting = term.stage == BootStage.booting;
    _maybeRunDeepLink(term);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Animated starfield, behind everything.
          Positioned.fill(
            child: StarfieldBackground(
              palette: palette,
              animate: !term.reduceMotion,
            ),
          ),

          // Content column.
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
                            if (_tab != 4)
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

          // CRT treatment on top, never blocking input.
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
        return const LogScreen();
      case 4:
        return const SystemScreen();
      default:
        return const ConsoleScreen();
    }
  }

  /// A one-line live ticker above the nav bar — the terminal's "chatter".
  Widget _logTicker(TerminalController term, Palette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: palette.line.withValues(alpha: 0.8)),
        color: palette.panel.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Text(
            '›',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 11,
              color: palette.bright,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _tickerText(term),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9.5,
                letterSpacing: 0.2,
                color: palette.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _tickerText(TerminalController term) {
    final b = term.brightestVisible;
    final lst = (term.lstDegrees / 15).toStringAsFixed(2);
    if (b == null) {
      return 'no catalogue objects above horizon · lst ${lst}h · '
          'moon ${term.moonGlyphValue}';
    }
    return 'brightest up: ${b.name} '
        '(${b.altitude.toStringAsFixed(0)}° ${b.magnitude.toStringAsFixed(2)}m)'
        ' · lst ${lst}h · moon ${term.moonGlyphValue} ${term.moonPhaseLabel}'
        ' · ${term.visibleCount}/${term.stars.length} plotted';
  }
}
