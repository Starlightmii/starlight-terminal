import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// LOG — one honest timeline of everything the app did.
///
/// This is the unified sink: pi turns, bridge traffic, agent tool calls,
/// scheduler firings and system events all land in the same stream, filterable
/// by severity and scope. The old screen only showed observer notes.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  LogLevel _floor = LogLevel.debug;
  String _scope = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final log = studio.appLog;

    var entries = log.all;
    if (_floor != LogLevel.debug) {
      entries = entries.where((e) => e.level.index >= _floor.index).toList();
    }
    if (_scope.isNotEmpty) {
      entries = entries
          .where((e) => e.scope.toLowerCase() == _scope.toLowerCase())
          .toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      entries = entries
          .where(
            (e) =>
                e.text.toLowerCase().contains(q) ||
                e.scope.toLowerCase().contains(q),
          )
          .toList();
    }

    return Column(
      children: [
        _header(palette, studio, log),
        const SizedBox(height: 8),
        _filters(palette, log),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'EVENT STREAM',
            accent: true,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            trailing: Text(
              '${entries.length}/${log.length}',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.dim,
              ),
            ),
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'no matching events',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 9,
                        color: palette.dim,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final color = switch (e.level) {
                        LogLevel.debug => palette.dim,
                        LogLevel.info => palette.mid,
                        LogLevel.tool => palette.warn,
                        LogLevel.warn => palette.warn,
                        LogLevel.error => palette.err,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.timeLabel,
                              style: TextStyle(
                                fontFamily: 'Mono',
                                fontSize: 7.5,
                                color: palette.dim.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(width: 5),
                            SizedBox(
                              width: 22,
                              child: Text(
                                e.levelLabel,
                                style: TextStyle(
                                  fontFamily: 'Mono',
                                  fontSize: 7,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 46,
                              child: Text(
                                e.scope,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Mono',
                                  fontSize: 7.5,
                                  color: palette.dim,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.text,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Mono',
                                  fontSize: 8,
                                  height: 1.35,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _header(Palette palette, StudioController studio, AppLog log) {
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SYSTEM LOG',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${log.countOf(LogLevel.error)} err · '
                '${log.countOf(LogLevel.warn)} warn · '
                '${log.countOf(LogLevel.tool)} tool · '
                '${log.length} total',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
            ],
          ),
          const Spacer(),
          _btn(palette, 'CLEAR', log.clear),
        ],
      ),
    );
  }

  Widget _filters(Palette palette, AppLog log) {
    final scopes = log.scopes.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final l in [
              LogLevel.debug,
              LogLevel.info,
              LogLevel.tool,
              LogLevel.warn,
              LogLevel.error,
            ]) ...[
              _chip(
                palette,
                l.name.toUpperCase(),
                _floor == l,
                () => setState(() => _floor = l),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip(palette, 'ALL', _scope.isEmpty, () {
                      setState(() => _scope = '');
                    }),
                    const SizedBox(width: 4),
                    for (final s in scopes) ...[
                      _chip(palette, s, _scope == s, () {
                        setState(() => _scope = _scope == s ? '' : s);
                      }),
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 110,
              height: 20,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.bright,
                ),
                cursorColor: palette.bright,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.bright),
                  ),
                  hintText: 'grep…',
                  hintStyle: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _btn(Palette palette, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: palette.line)),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: palette.mid,
          ),
        ),
      ),
    );
  }

  Widget _chip(
    Palette palette,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: active ? palette.bright : palette.line),
          color: active
              ? palette.bright.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }
}
