import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/memory.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// MEMORY — every durable thing learned in a conversation, laid out as a map.
///
/// Each memory is a node; nodes sharing a session pull together, and pinning
/// raises a node's weight so it stays through eviction.
///
/// Hit-testing used to be computed against the *whole screen's* RenderBox while
/// the tap offset was local to the map, so every tap missed and the section read
/// as "not clickable". The map now owns its own `LayoutBuilder` size, and a
/// readable list below the chart gives every memory a guaranteed tap target.
class SkyMapScreen extends StatefulWidget {
  const SkyMapScreen({super.key});

  @override
  State<SkyMapScreen> createState() => _SkyMapScreenState();
}

class _SkyMapScreenState extends State<SkyMapScreen> {
  String _source = '';
  String _query = '';
  Memory? _selected;
  bool _listMode = false;

  static const Map<String, String> _sources = {
    '': 'ALL',
    'pi': 'PI',
    'bot': 'BOT',
    'agent': 'AGENT',
    'console': 'CONSOLE',
    'system': 'SYS',
  };

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final mem = studio.memory;

    final visible = mem.all.where((m) {
      if (_source.isNotEmpty && m.source.name != _source) return false;
      if (_query.isNotEmpty &&
          !m.text.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    // A selection that the current filter hides would strand the detail panel.
    if (_selected != null && !visible.any((m) => m.id == _selected!.id)) {
      _selected = null;
    }

    return Column(
      children: [
        _header(studio, palette, mem, visible.length),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: _listMode ? 'MEMORY INDEX' : 'MEMORY MAP',
            accent: true,
            padding: const EdgeInsets.all(6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${visible.length} nodes',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _listMode = !_listMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.line),
                    ),
                    child: Text(
                      _listMode ? '◉ MAP' : '☰ LIST',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: palette.mid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            child: visible.isEmpty
                ? _empty(palette)
                : _listMode
                    ? _indexList(palette, visible)
                    : _chart(palette, visible),
          ),
        ),
        const SizedBox(height: 8),
        if (_selected != null) _detail(palette, _selected!),
      ],
    );
  }

  // ── Chart ──────────────────────────────────────────────────────────────

  Widget _chart(Palette palette, List<Memory> visible) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          // opaque, not translucent: taps on the empty space between nodes
          // should still clear the selection rather than fall through.
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _hit(d.localPosition, visible, size),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CustomPaint(
              painter: _MemoryMapPainter(
                memories: visible,
                palette: palette,
                selected: _selected?.id,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }

  /// Find the nearest node to [at] in *map-local* coordinates.
  void _hit(Offset at, List<Memory> visible, Size size) {
    Memory? best;
    // Generous radius: a fingertip is about 40dp wide, and the spiral can put
    // two nodes close together on a narrow phone.
    var bestD = 44.0;
    for (var i = 0; i < visible.length; i++) {
      final p = _MemoryMapPainter.nodePosition(i, visible.length, size);
      final d = (p - at).distance;
      if (d < bestD) {
        bestD = d;
        best = visible[i];
      }
    }
    setState(() => _selected = best);
  }

  Widget _indexList(Palette palette, List<Memory> visible) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: palette.line.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, i) {
        final m = visible[i];
        final selected = m.id == _selected?.id;
        final tint = _sourceColor(palette, m.source);
        return InkWell(
          onTap: () => setState(() => _selected = m),
          child: Container(
            color: selected ? tint.withValues(alpha: 0.10) : null,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 5, right: 7),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _oneLine(m.text, 120),
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 10,
                          height: 1.35,
                          color: selected ? palette.bright : palette.mid,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${m.source.name} · ${m.ageLabel}'
                        '${m.starId != null ? ' · ★ pinned' : ''}',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 8,
                          color: palette.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _sourceColor(Palette p, MemorySource s) => switch (s) {
        MemorySource.pi => p.ok,
        MemorySource.agent => p.warn,
        MemorySource.bot => p.mid,
        MemorySource.console => p.dim,
        MemorySource.system => p.err,
      };

  static String _oneLine(String s, int max) {
    final flat = s.replaceAll('\n', ' ').trim();
    return flat.length > max ? '${flat.substring(0, max)}…' : flat;
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _header(
    StudioController studio,
    Palette palette,
    MemoryStore mem,
    int shown,
  ) {
    final breakdown = mem.sourceBreakdown;
    return TermPanel(
      palette: palette,
      // Header: unbounded height, so the body must shrink-wrap.
      expand: false,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MEMORY',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${mem.length} stored · ${mem.anchored.length} pinned',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
              const Spacer(),
              Text(
                '$shown shown',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 22,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _sources.entries.map((e) {
                final on = _source == e.key;
                final n = e.key.isEmpty ? mem.length : (breakdown[e.key] ?? 0);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _source = e.key),
                  child: Container(
                    margin: const EdgeInsets.only(right: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: on ? palette.bright : palette.line,
                      ),
                      color: on
                          ? palette.bright.withValues(alpha: 0.10)
                          : Colors.transparent,
                    ),
                    child: Text(
                      '${e.value} $n',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: on ? palette.bright : palette.dim,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 24,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 10,
                color: palette.bright,
              ),
              cursorColor: palette.bright,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, size: 13, color: palette.dim),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 22, minHeight: 0),
                hintText: 'grep memories',
                hintStyle: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  color: palette.dim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(Palette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '◌',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 30,
                color: palette.dim,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No memories yet.',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: palette.mid,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Talk to pi, run an agent, or use the console.\n'
              'Every turn that produces something durable lands here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9.5,
                height: 1.5,
                color: palette.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(Palette palette, Memory m) {
    final tint = _sourceColor(palette, m.source);
    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m.source.name.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                m.ageLabel,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: palette.dim,
                ),
              ),
              const Spacer(),
              if (m.starId != null)
                Text(
                  '★ pinned',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.warn,
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = null),
                child: Text(
                  '✕',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 10,
                    color: palette.dim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9.5,
              height: 1.4,
              color: palette.mid,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays memories out on an Archimedean spiral.
///
/// A spiral keeps every node reachable without collisions as the count grows.
class _MemoryMapPainter extends CustomPainter {
  _MemoryMapPainter({
    required this.memories,
    required this.palette,
    this.selected,
  });

  final List<Memory> memories;
  final Palette palette;
  final String? selected;

  static Offset nodePosition(int i, int total, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // 0.40 leaves room for the glow halo without clipping at the panel edge.
    final maxR = math.min(size.width, size.height) * 0.40;
    final t = total <= 1 ? 0.0 : i / total;
    final angle = i * 2.399963; // golden angle spreads the arms evenly
    final r = maxR * math.sqrt(t);
    return c + Offset(math.cos(angle) * r, math.sin(angle) * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.40;

    // Reference rings.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = palette.line.withValues(alpha: 0.55);
    for (var k = 1; k <= 3; k++) {
      canvas.drawCircle(c, maxR * k / 3, ring);
    }

    // Edges: same-session memories pull together.
    final bySession = <String, List<int>>{};
    for (var i = 0; i < memories.length; i++) {
      final sid = memories[i].sessionId;
      if (sid == null || sid.isEmpty) continue;
      bySession.putIfAbsent(sid, () => []).add(i);
    }
    final edge = Paint()
      ..strokeWidth = 0.7
      ..color = palette.dim.withValues(alpha: 0.25);
    bySession.forEach((_, idx) {
      for (var k = 1; k < idx.length; k++) {
        canvas.drawLine(
          nodePosition(idx[k - 1], memories.length, size),
          nodePosition(idx[k], memories.length, size),
          edge,
        );
      }
    });

    // Nodes.
    for (var i = 0; i < memories.length; i++) {
      final m = memories[i];
      final p = nodePosition(i, memories.length, size);
      final isSel = m.id == selected;
      final pinned = m.starId != null && m.starId!.isNotEmpty;
      final r = 2.4 + (m.weight.clamp(0.0, 1.0) * 2.6) + (pinned ? 1.2 : 0);

      final color = switch (m.source) {
        MemorySource.pi => palette.ok,
        MemorySource.agent => palette.warn,
        MemorySource.bot => palette.mid,
        MemorySource.console => palette.dim,
        MemorySource.system => palette.err,
      };

      canvas.drawCircle(
        p,
        r * 2.6,
        Paint()
          ..color = color.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(p, r, Paint()..color = color);

      if (isSel) {
        canvas.drawCircle(
          p,
          r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = palette.bright,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MemoryMapPainter old) =>
      old.memories.length != memories.length ||
      old.selected != selected ||
      old.palette != palette;
}
