import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/agent_runtime.dart';
import '../../core/palette.dart';
import '../../core/providers.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';

/// Multi-agent control room: pick a fleet mode, brief them, watch them work.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  final TextEditingController _brief = TextEditingController();
  final ScrollController _feedScroll = ScrollController();
  int _lastFeedLen = 0;

  @override
  void dispose() {
    _brief.dispose();
    _feedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;

    if (studio.feed.length != _lastFeedLen) {
      _lastFeedLen = studio.feed.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_feedScroll.hasClients) _feedScroll.jumpTo(0);
      });
    }

    return Column(
      children: [
        _briefBar(studio, palette),
        const SizedBox(height: 8),
        Expanded(child: _fleetList(studio, palette)),
        const SizedBox(height: 8),
        _eventFeed(studio, palette),
      ],
    );
  }

  // ── Brief bar ───────────────────────────────────────────────────────────

  Widget _briefBar(StudioController studio, Palette palette) {
    final ready = studio.configuredCount;
    return TermPanel(
      palette: palette,
      accent: true,
      title: 'ORCHESTRATOR',
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      trailing: Row(
        children: [
          Text(
            ready == 0 ? 'NO KEYS' : '$ready KEY${ready == 1 ? '' : 'S'}',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: ready == 0 ? palette.warn : palette.ok,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _brief,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11.5,
                    color: palette.bright,
                  ),
                  cursorColor: palette.bright,
                  cursorWidth: 5,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'brief the fleet…',
                    hintStyle: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 11.5,
                      color: palette.dim,
                    ),
                  ),
                  onSubmitted: (_) => _runFleet(studio),
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(
                palette,
                studio.orchestrating ? 'WORKING' : 'DISPATCH',
                onTap: studio.orchestrating ? null : () => _runFleet(studio),
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in OrchestrationMode.values) ...[
                _modeChip(studio, palette, m),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _runFleet(StudioController studio) {
    final task = _brief.text.trim();
    if (task.isEmpty) return;
    studio.dispatchFleet(task);
    _brief.clear();
  }

  Widget _modeChip(
    StudioController studio,
    Palette palette,
    OrchestrationMode m,
  ) {
    final active = studio.mode == m;
    final label = switch (m) {
      OrchestrationMode.broadcast => 'BROADCAST',
      OrchestrationMode.pipeline => 'PIPELINE',
      OrchestrationMode.dispatch => 'DISPATCH',
    };
    return InkWell(
      onTap: () => studio.setMode(m),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? palette.mid.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: active ? palette.mid : palette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              letterSpacing: 0.9,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? palette.bright : palette.dim,
            ),
          ),
        ),
    );
  }

  // ── Fleet ───────────────────────────────────────────────────────────────

  Widget _fleetList(StudioController studio, Palette palette) {
    final agents = studio.agents;
    return TermPanel(
      palette: palette,
      title: 'FLEET',
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      trailing: Text(
        '${agents.where((a) => a.busy).length} ACTIVE',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          letterSpacing: 1.1,
          color: palette.dim,
        ),
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: agents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) => _agentCard(studio, palette, agents[i]),
      ),
    );
  }

  Widget _agentCard(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) {
    final accent = _agentColor(palette, agent.colorIndex);
    final provider = studio.byId(agent.providerId);
    final live = provider != null &&
        provider.ready &&
        provider.looksPlausible &&
        provider.kind == ProviderKind.llm;

    final lastLine = agent.transcript.isEmpty
        ? null
        : agent.transcript.last;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accent, width: 2),
          top: BorderSide(color: palette.line),
          right: BorderSide(color: palette.line),
          bottom: BorderSide(color: palette.line),
        ),
        color: palette.bg.withValues(alpha: 0.35),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                agent.enabled ? '●' : '○',
                style: TextStyle(fontSize: 9, color: accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  agent.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: agent.enabled ? palette.bright : palette.dim,
                  ),
                ),
              ),
              _stateTag(agent, palette),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${provider?.label ?? 'unbound'} · '
                  '${live ? 'LIVE' : 'OFFLINE'} · '
                  '${agent.toolCalls} tools',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: live ? palette.ok : palette.dim,
                  ),
                ),
              ),
              _iconTap(
                palette,
                agent.busy ? '■' : '▶',
                () {
                  if (agent.busy) {
                    studio.cancelAgent(agent.id);
                  } else {
                    final task = _brief.text.trim().isEmpty
                        ? 'Survey what is visible and summarise the sky.'
                        : _brief.text.trim();
                    studio.runAgent(agent.id, task);
                  }
                },
              ),
              _iconTap(palette, '↺', () => studio.resetAgent(agent.id)),
              _iconTap(
                palette,
                agent.enabled ? '◉' : '○',
                () => studio.toggleAgent(agent.id),
              ),
            ],
          ),
          if (lastLine != null) ...[
            const SizedBox(height: 4),
            Text(
              '${lastLine.prefix}> ${_oneLine(lastLine.text)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9,
                height: 1.25,
                color: lastLine.role == AgentRole.tool
                    ? palette.dim
                    : palette.mid,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _oneLine(String s) {
    final flat = s.replaceAll('\n', ' · ').trim();
    return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
  }

  Color _agentColor(Palette p, int i) {
    const tints = [
      Color(0xFF7CFFC4),
      Color(0xFF6FC6FF),
      Color(0xFFFFCF6B),
      Color(0xFFD6A8FF),
    ];
    return tints[i % tints.length];
  }

  Widget _stateTag(AgentRuntime agent, Palette p) {
    final (label, color) = switch (agent.state) {
      AgentRunState.idle => ('IDLE', p.dim),
      AgentRunState.thinking => ('THINK', p.warn),
      AgentRunState.toolCall => ('TOOL', p.mid),
      AgentRunState.done => ('DONE', p.ok),
      AgentRunState.error => ('ERR', p.err),
      AgentRunState.cancelled => ('STOP', p.warn),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 7.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _iconTap(Palette p, String glyph, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          glyph,
          style: TextStyle(fontFamily: 'Mono', fontSize: 11, color: p.mid),
        ),
      ),
    );
  }

  // ── Feed ────────────────────────────────────────────────────────────────

  Widget _eventFeed(StudioController studio, Palette palette) {
    final events = studio.feed;
    return SizedBox(
      height: 108,
      child: TermPanel(
        palette: palette,
        title: 'EVENT STREAM',
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        trailing: Text(
          '${events.length}',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8.5,
            color: palette.dim,
          ),
        ),
        child: events.isEmpty
            ? Center(
                child: Text(
                  'no agent activity yet — dispatch a brief above',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 9.5,
                    color: palette.dim,
                  ),
                ),
              )
            : ListView.builder(
                controller: _feedScroll,
                reverse: true,
                padding: EdgeInsets.zero,
                itemCount: events.length,
                itemBuilder: (context, i) {
                  final e = events[events.length - 1 - i];
                  final (glyph, color) = switch (e.kind) {
                    AgentEventKind.thinking => ('·', palette.warn),
                    AgentEventKind.tool => ('→', palette.mid),
                    AgentEventKind.toolResult => ('←', palette.dim),
                    AgentEventKind.message => ('»', palette.bright),
                    AgentEventKind.done => ('✓', palette.ok),
                    AgentEventKind.warn => ('!', palette.warn),
                    AgentEventKind.info => ('i', palette.dim),
                  };
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      '$glyph ${_oneLine(e.text)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 9,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _actionButton(
    Palette palette,
    String label, {
    VoidCallback? onTap,
    bool filled = false,
  }) {
    final color = onTap == null ? palette.dim : palette.bright;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.7)),
          color: filled
              ? palette.mid.withValues(alpha: onTap == null ? 0.04 : 0.16)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 9.5,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
