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
        _schedulerBar(studio, palette),
        const SizedBox(height: 8),
        Expanded(child: _fleetList(studio, palette)),
        const SizedBox(height: 8),
        _eventFeed(studio, palette),
      ],
    );
  }

  /// Autonomous-run status: heartbeat, armed count, recent firings.

  /// Craft a new agent: a name plus the persona that shapes its turns.
  Future<void> _craftDialog(StudioController studio, Palette palette) async {
    final name = TextEditingController();
    final persona = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.panel,
        shape: const RoundedRectangleBorder(),
        title: Text(
          'CRAFT AGENT',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: palette.bright,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(name, palette, 'NAME', 'e.g. SCOUT'),
            const SizedBox(height: 8),
            _field(persona, palette, 'PERSONA', 'what it does, how it answers',
                lines: 3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL',
                style: TextStyle(
                    fontFamily: 'Mono', fontSize: 9, color: palette.dim)),
          ),
          TextButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              studio.addAgent(
                name: n,
                persona: persona.text.trim().isEmpty
                    ? 'You are $n, a helpful agent running on the pi backend.'
                    : persona.text.trim(),
              );
              studio.appLog.info('crafted agent $n', scope: 'agents');
              Navigator.pop(ctx);
            },
            child: Text('CREATE',
                style: TextStyle(
                    fontFamily: 'Mono', fontSize: 9, color: palette.bright)),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    Palette palette,
    String label,
    String hint, {
    int lines = 1,
  }) {
    return TextField(
      controller: c,
      maxLines: lines,
      style: TextStyle(fontFamily: 'Mono', fontSize: 10, color: palette.bright),
      cursorColor: palette.bright,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
            fontFamily: 'Mono', fontSize: 9, color: palette.dim),
        hintStyle:
            TextStyle(fontFamily: 'Mono', fontSize: 9, color: palette.dim),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: palette.bright),
        ),
      ),
    );
  }

  Widget _schedulerBar(StudioController studio, Palette palette) {
    final sch = studio.scheduler;
    final armed = sch.armedCount;
    final last = sch.history.isEmpty ? null : sch.history.first;

    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sch.enabled ? palette.ok : palette.dim,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'SCHEDULER',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: palette.bright,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            sch.enabled ? 'running' : 'paused',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              color: sch.enabled ? palette.ok : palette.dim,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$armed armed',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8,
              color: armed > 0 ? palette.warn : palette.dim,
            ),
          ),
          if (last != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'last: ${last.agentName.toLowerCase()} ${last.ageLabel}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8,
                  color: palette.dim,
                ),
              ),
            ),
          ],
          const Spacer(),
          InkWell(
            onTap: () {
              sch.setEnabled(!sch.enabled);
              setState(() {});
            },
            child: Text(
              sch.enabled ? 'PAUSE' : 'RESUME',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 7.5,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: palette.bright,
              ),
            ),
          ),
        ],
      ),
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
      title: 'AGENTS',
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${agents.where((a) => a.busy).length} ACTIVE',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 8.5,
              letterSpacing: 1.1,
              color: palette.dim,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _craftDialog(studio, palette),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: palette.bright.withValues(alpha: 0.5)),
              ),
              child: Text(
                '+ CRAFT',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
            ),
          ),
        ],
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
          const SizedBox(height: 5),
          _scheduleRow(studio, palette, agent),
        ],
      ),
    );
  }

  /// Autonomous-run controls: arm/disarm, interval, standing task, run now.
  Widget _scheduleRow(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) {
    final next = studio.scheduler.nextDueIn(agent);
    final due = studio.scheduler.isDue(agent);
    final armed = agent.autoRun && agent.task.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  final newTask = agent.task.trim().isEmpty
                      ? 'Survey what is visible and summarise the sky.'
                      : agent.task;
                  studio.setAgentSchedule(
                    agent.id,
                    autoRun: !agent.autoRun,
                    task: newTask,
                  );
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: armed ? palette.ok : palette.line,
                    ),
                    color: armed
                        ? palette.ok.withValues(alpha: 0.1)
                        : Colors.transparent,
                  ),
                  child: Text(
                    armed ? '⟳ AUTO ON' : '⟳ AUTO OFF',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: armed ? palette.ok : palette.dim,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _intervalStepper(studio, palette, agent),
              const SizedBox(width: 5),
              InkWell(
                onTap: () => _editTask(studio, palette, agent),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration:
                      BoxDecoration(border: Border.all(color: palette.line)),
                  child: Text(
                    agent.task.trim().isEmpty ? 'SET TASK' : 'EDIT TASK',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: palette.mid,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () async {
                  if (agent.task.trim().isEmpty) {
                    await _editTask(studio, palette, agent);
                    return;
                  }
                  await studio.runAgentNow(agent.id);
                  if (mounted) setState(() {});
                },
                child: Text(
                  'RUN NOW',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 7,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: palette.bright,
                  ),
                ),
              ),
            ],
          ),
          if (agent.task.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '⟳ ${_oneLine(agent.task)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.dim,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            armed
                ? (due
                    ? 'due now · ${agent.autoRuns} runs'
                    : 'next in ${_shortDuration(next)} · ${agent.autoRuns} runs')
                : 'manual only · ${agent.autoRuns} auto runs',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7.5,
              color: armed && due ? palette.warn : palette.dim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _intervalStepper(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) {
    const stops = [5, 15, 30, 60, 180, 360, 720, 1440];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: palette.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              final i = stops.indexOf(agent.everyMinutes);
              final next = i <= 0 ? stops.first : stops[i - 1];
              studio.setAgentSchedule(agent.id, everyMinutes: next);
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '−',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9,
                  color: palette.mid,
                ),
              ),
            ),
          ),
          Text(
            _shortMinutes(agent.everyMinutes),
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: palette.mid,
            ),
          ),
          InkWell(
            onTap: () {
              final i = stops.indexOf(agent.everyMinutes);
              final next = i < 0 || i >= stops.length - 1
                  ? stops.last
                  : stops[i + 1];
              studio.setAgentSchedule(agent.id, everyMinutes: next);
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '+',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 9,
                  color: palette.mid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortMinutes(int m) {
    if (m >= 1440) return '24h';
    if (m >= 60) return '${m ~/ 60}h';
    return '${m}m';
  }

  String _shortDuration(Duration? d) {
    if (d == null) return '—';
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return '${d.inHours}h${m == 0 ? '' : '${m}m'}';
    }
    return '${d.inMinutes}m';
  }

  Future<void> _editTask(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) async {
    final ctrl = TextEditingController(text: agent.task);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.panel,
        title: Text(
          'STANDING TASK · ${agent.name}',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 12,
            color: palette.bright,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 11,
            color: palette.bright,
          ),
          decoration: InputDecoration(
            hintText: 'what should this agent do on every run?',
            hintStyle: TextStyle(
              fontFamily: 'Mono',
              fontSize: 10,
              color: palette.dim,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL',
                style: TextStyle(fontFamily: 'Mono', color: palette.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('SAVE',
                style: TextStyle(fontFamily: 'Mono', color: palette.bright)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    studio.setAgentSchedule(agent.id, task: result.trim());
    if (mounted) setState(() {});
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
