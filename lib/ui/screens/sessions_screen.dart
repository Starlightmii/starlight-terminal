import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/memory.dart';
import '../../core/palette.dart';
import '../../core/session_store.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// SESSIONS — every conversation the operator has had, plus the memories those
/// conversations produced. This replaces the old star catalogue tab: the
/// catalogue still exists (it drives the MAP and the sky maths), but the thing
/// worth browsing here is what the app *learned*.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionKind? _kindFilter;
  String _query = '';
  bool _showMemories = false;

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final store = studio.sessions;

    var list = store.all;
    if (_kindFilter != null) {
      list = list.where((s) => s.kind == _kindFilter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where(
            (s) =>
                s.title.toLowerCase().contains(q) ||
                s.preview.toLowerCase().contains(q) ||
                s.tags.any((t) => t.contains(q)),
          )
          .toList();
    }
    final active = store.active;

    return Column(
      children: [
        _summary(palette, studio),
        const SizedBox(height: 8),
        _filterBar(palette),
        const SizedBox(height: 8),
        Expanded(
          child: _showMemories
              ? _memoryPane(palette, studio)
              : (list.isEmpty
                  ? _empty(palette)
                  : _list(palette, studio, list, active)),
        ),
      ],
    );
  }

  Widget _summary(Palette palette, StudioController studio) {
    final st = studio.sessions.stats;
    final piCount = studio.sessions.byKind(SessionKind.pi).length;
    final jobCount = studio.sessions.byKind(SessionKind.job).length;

    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION JOURNAL',
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
                      '${st['sessions']} sessions · ${st['messages']} messages · '
                      '${st['memories']} memories stored',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8.5,
                        color: palette.dim,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${st['memories']}',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: (st['memories'] ?? 0) > 0
                          ? palette.ok
                          : palette.dim,
                      shadows: [
                        Shadow(
                          color: palette.ok.withValues(alpha: 0.7),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'MEMORIES',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7,
                      letterSpacing: 1.1,
                      color: palette.dim,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _stat(palette, 'PI', '$piCount'),
              const SizedBox(width: 10),
              _stat(palette, 'JOBS', '$jobCount'),
              const SizedBox(width: 10),
              _stat(palette, 'TOOLS', '${st['tools']}'),
              const SizedBox(width: 10),
              _stat(palette, 'ERR', '${st['errors']}'),
              const Spacer(),
              _chip(
                palette,
                _showMemories ? '← SESSIONS' : 'MEMORIES →',
                false,
                () => setState(() => _showMemories = !_showMemories),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(Palette palette, String k, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$k ',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7.5,
              letterSpacing: 0.8,
              color: palette.dim,
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: palette.mid,
            ),
          ),
        ],
      );

  Widget _filterBar(Palette palette) {
    return Row(
      children: [
        _chip(palette, 'ALL', _kindFilter == null, () {
          setState(() => _kindFilter = null);
        }),
        const SizedBox(width: 4),
        for (final k in SessionKind.values) ...[
          _chip(palette, k.name.toUpperCase(), _kindFilter == k, () {
            setState(() => _kindFilter = k);
          }),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(border: Border.all(color: palette.line)),
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
                border: InputBorder.none,
                hintText: 'search sessions…',
                hintStyle: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(Palette palette) => TermPanel(
        palette: palette,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '○',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 30,
                  color: palette.dim.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No sessions yet.',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  color: palette.mid,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Talk to pi in the PI tab, or arm an agent in AGENTS.\n'
                'Every conversation lands here and feeds the map.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  height: 1.45,
                  color: palette.dim,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _list(
    Palette palette,
    StudioController studio,
    List<ChatSession> list,
    ChatSession? active,
  ) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final s = list[i];
        final isActive = active?.id == s.id;
        final memCount = studio.memory.forSession(s.id).length;
        return InkWell(
          onTap: () {
            studio.sessions.setActive(s.id);
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            decoration: BoxDecoration(
              color: isActive
                  ? palette.bright.withValues(alpha: 0.06)
                  : palette.panel.withValues(alpha: 0.5),
              border: Border.all(
                color: isActive ? palette.bright : palette.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      s.pinned ? '★' : '○',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 9,
                        color: s.pinned ? palette.warn : palette.dim,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        s.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isActive ? palette.bright : palette.mid,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      s.kindLabel,
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 7,
                        letterSpacing: 1,
                        color: palette.dim,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.ageLabel,
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 7.5,
                        color: palette.dim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  s.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    height: 1.35,
                    color: palette.dim,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${s.messageCount} msg · ${s.toolCalls} tools · '
                      '$memCount mem',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 7.5,
                        color: palette.dim,
                      ),
                    ),
                    const Spacer(),
                    if (s.errorCount > 0)
                      Text(
                        '${s.errorCount} err',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 7.5,
                          color: palette.err,
                        ),
                      ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 6),
                  Divider(color: palette.line, height: 1),
                  const SizedBox(height: 6),
                  _detail(palette, studio, s),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detail(Palette palette, StudioController studio, ChatSession s) {
    final mems = studio.memory.forSession(s.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _mini(palette, s.pinned ? 'UNPIN' : 'PIN', () {
              s.pinned = !s.pinned;
              setState(() {});
            }),
            const SizedBox(width: 5),
            _mini(palette, 'DELETE', () {
              studio.sessions.remove(s.id);
              setState(() {});
            }),
            const Spacer(),
            Text(
              'tok ${s.tokensIn}/${s.tokensOut}',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 7.5,
                color: palette.dim,
              ),
            ),
          ],
        ),
        if (mems.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'MEMORIES FROM THIS SESSION',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: palette.dim,
            ),
          ),
          const SizedBox(height: 3),
          for (final m in mems.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.starId != null ? '★' : '·',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 8,
                      color: m.starId != null ? palette.warn : palette.dim,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      m.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8,
                        height: 1.35,
                        color: palette.mid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _memoryPane(Palette palette, StudioController studio) {
    final mems = studio.memory.all;
    if (mems.isEmpty) {
      return TermPanel(
        palette: palette,
        child: Center(
          child: Text(
            'no memories yet — chat with pi or a bot and they accumulate here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              height: 1.4,
              color: palette.dim,
            ),
          ),
        ),
      );
    }
    return TermPanel(
      palette: palette,
      title: 'MEMORY STORE',
      accent: true,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      trailing: Text(
        '${mems.length} · cap ${studio.memory.capacity}',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8,
          color: palette.dim,
        ),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: mems.length,
        itemBuilder: (context, i) {
          final m = mems[i];
          final color = switch (m.source) {
            MemorySource.pi => palette.bright,
            MemorySource.agent => palette.warn,
            MemorySource.bot => palette.mid,
            MemorySource.system => palette.err,
            MemorySource.console => palette.dim,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    m.source.name.toUpperCase().substring(0, 3),
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7,
                      color: color,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    m.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 8.5,
                      height: 1.4,
                      color: palette.mid,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  m.ageLabel,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 7,
                    color: palette.dim,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _mini(Palette palette, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: palette.line)),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 7,
            letterSpacing: 0.8,
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
            fontSize: 7.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: active ? palette.bright : palette.dim,
          ),
        ),
      ),
    );
  }
}
