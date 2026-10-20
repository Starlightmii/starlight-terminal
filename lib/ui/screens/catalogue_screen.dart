import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue.dart';
import '../../core/console_engine.dart';
import '../../core/palette.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';

/// Searchable catalogue browser. Mirror of the `find` command, but browsable.
class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _visibleOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;

    var items = term.stars.toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      items = items
          .where(
            (s) =>
                s.name.toLowerCase().contains(q) ||
                s.constellation.toLowerCase().contains(q) ||
                s.bayer.toLowerCase().contains(q) ||
                s.spectral.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_visibleOnly) {
      items = items.where((s) => s.altitude > 0).toList();
    }

    return Column(
      children: [
        _searchBar(term, palette),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'CATALOGUE',
            accent: true,
            padding: EdgeInsets.zero,
            trailing: Text(
              '${items.length} OBJ',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: palette.mid,
              ),
            ),
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'no objects match "$_query"',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 11.5,
                        color: palette.dim,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: palette.line.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (context, i) => _row(items[i], term, palette),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _searchBar(TerminalController term, Palette palette) {
    return Column(
      children: [
        TermPanel(
          palette: palette,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              Text(
                '»',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 16,
                  color: palette.dim,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 12.5,
                    color: palette.bright,
                  ),
                  cursorColor: palette.bright,
                  cursorWidth: 5,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'filter by name, constellation, spectral…',
                    hintStyle: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 11.5,
                      color: palette.dim.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                InkWell(
                  onTap: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '✕',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 14,
                        color: palette.dim,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _toggle(
              'ABOVE HORIZON ONLY',
              _visibleOnly,
              palette,
              () => setState(() => _visibleOnly = !_visibleOnly),
            ),
            const Spacer(),
            Text(
              '${term.visibleCount} up now',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                color: palette.dim,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toggle(String label, bool on, Palette palette, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: on ? palette.mid : palette.line),
          color: on ? palette.mid.withValues(alpha: 0.10) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              on ? '■' : '□',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                color: on ? palette.bright : palette.dim,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: on ? palette.bright : palette.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Star s, TerminalController term, Palette palette) {
    final up = s.altitude > 0;
    final tint = spectralColor(s.spectral);
    final isSelected = term.selectedStar?.id == s.id;

    return InkWell(
      onTap: () {
        term.selectStar(s);
        term.runCommand('star ${s.name.toLowerCase()}');
      },
      child: Container(
        color: isSelected ? palette.mid.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: up ? tint : palette.line,
                boxShadow: up
                    ? [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                s.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: up ? palette.bright : palette.dim,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                s.constellation.split(' ').first,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  color: palette.dim,
                ),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                fmtMag(s.magnitude),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  color: palette.mid,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                up ? '${s.altitude.toStringAsFixed(0)}°' : '↓',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10.5,
                  color: up ? palette.ok : palette.line,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
