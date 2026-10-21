import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/memory.dart';
import '../../core/palette.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// MEMORY — every durable thing learned in a conversation, laid out as a map.
///
/// The old version plotted a star catalogue on a sky chart. Stars were never
/// the point of this app, and they crowded out the thing that actually
/// accumulates: memory. Each memory is a node; nodes sharing a session pull
/// together, and pinning raises a node's weight so it stays through eviction.
class SkyMapScreen extends StatefulWidget {
  const SkyMapScreen({super.key});

  @override
  State<SkyMapScreen> createState() => _SkyMapScreenState();
}

class _SkyMapScreenState extends State<SkyMapScreen> {
  String _source = '';
  String _query = '';
  Memory? _selected;

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

    return Column(
      children: [
        _header(studio, palette, mem, visible.length),
        const SizedBox(height: 8),
        Expanded(
          child: TermPanel(
            palette: palette,
            title: 'MEMORY MAP',
            accent: true,
            padding: const EdgeInsets.all(6),
            trailing: Text(
              '${visible.length} nodes',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8.5,
                color: palette.dim,
              ),
            ),
            child: visible.isEmpty
                ? _empty(palette)
                : GestureDetector(
                    onTapDown: (d) => _hit(d.localPosition, visible),
                    child: CustomPaint(
                      painter: _MemoryMapPainter(
                        memories: visible,
                        palette: palette,
                        selected: _selected?.id,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (_selected != null) _detail(palette, _selected!),
      ],
    );
  }

  void _hit(Offset at, List<Memory> visible) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Nodes are laid out on a spiral in normalised space; find the nearest.
    Memory? best;
    var bestD = 40.0;
    for (var i = 0; i < visible.length; i++) {
      final p = _MemoryMapPainter.nodePosition(i, visible.length, box.size);
      final d = (p - at).distance;
      if (d < bestD) {
        bestD = d;
        best = visible[i];
      }
    }
    setState(() => _selected = best);
  }

  Widget _header(
    StudioController studio,
    Palette palette,
    MemoryStore mem,
    int shown,
  ) {
    final breakdown = mem.sourceBreakdown;
    return TermPanel(
      palette: palette,
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
              style: TextStyle(fontFamily: 'Mono', fontSize: 30, color: palette.dim),
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
    return TermPanel(
      palette: palette,
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
                  color: palette.warn,
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
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.text,
            maxLines: 3,
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

/// Lays memories out on an Archimedean spiral, one arm per source.
///
/// A spiral keeps every node reachable without collisions as the count grows,
/// and grouping by source means the same conversation clusters visually.
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
    final maxR = math.min(size.width, size.height) * 0.44;
    final t = total <= 1 ? 0.0 : i / total;
    final angle = i * 2.399963; // golden angle spreads the arms evenly
    final r = maxR * math.sqrt(t);
    return c + Offset(math.cos(angle) * r, math.sin(angle) * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.44;

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
      final r = 2.2 + (m.weight.clamp(0.0, 1.0) * 2.6) + (pinned ? 1.2 : 0);

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
