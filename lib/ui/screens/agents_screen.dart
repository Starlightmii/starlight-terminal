import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/agent_runtime.dart';
import '../../core/palette.dart';
import '../../core/providers.dart';
import '../../state/studio_controller.dart';
import '../widgets/chrome.dart';
import '../widgets/term_keys.dart';

/// Multi-agent control room: brief the fleet, schedule it, watch it work.
///
/// The schedule/model/run controls always existed, but they lived in a
/// fixed-height `Column` whose `Expanded` list collapsed to zero pixels on a
/// phone — so the card bodies, and every control inside them, were unreachable.
/// The whole screen is now one scroll view with fixed-height panels, which puts
/// auto-run, the interval, the model picker and RUN NOW on screen for every
/// agent.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  final TextEditingController _brief = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _briefFocus = FocusNode();
  String _filter = 'ALL';

  @override
  void dispose() {
    _brief.dispose();
    _scroll.dispose();
    _briefFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioController>();
    final palette = studio.terminal.palette;
    final agents = studio.agents;

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        _briefBar(studio, palette),
        const SizedBox(height: 8),
        _schedulerBar(studio, palette),
        const SizedBox(height: 8),
        _fleetToolbar(studio, palette, agents.length),
        const SizedBox(height: 6),
        if (agents.isEmpty)
          _emptyFleet(palette)
        else
          for (final a in agents) ...[
            if (_filter == 'ALL' || _filter == 'AUTO' ? (a.autoRun || _filter == 'ALL') : true)
              _agentCard(studio, palette, a),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 2),
        _runHistory(studio, palette),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Brief / orchestrator ───────────────────────────────────────────────

  Widget _briefBar(StudioController studio, Palette palette) {
    final ready = studio.configuredCount;
    return TermPanel(
      palette: palette,
      expand: false,
      accent: true,
      title: 'ORCHESTRATOR',
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      trailing: Text(
        ready == 0 ? 'NO KEYS' : '$ready KEY${ready == 1 ? '' : 'S'}',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: ready == 0 ? palette.warn : palette.ok,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _brief,
                  focusNode: _briefFocus,
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in OrchestrationMode.values)
                _modeChip(studio, palette, m),
            ],
          ),
        ],
      ),
    );
  }

  void _runFleet(StudioController studio) {
    final task = _brief.text.trim();
    if (task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('type a brief first')),
      );
      return;
    }
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
          border: Border.all(color: active ? palette.mid : palette.line),
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

  // ── Scheduler ──────────────────────────────────────────────────────────

  Widget _schedulerBar(StudioController studio, Palette palette) {
    final sch = studio.scheduler;
    final armed = sch.armedCount;
    final last = sch.history.isEmpty ? null : sch.history.first;

    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const Spacer(),
              _mini(
                palette,
                sch.enabled ? 'PAUSE' : 'RESUME',
                () {
                  sch.setEnabled(!sch.enabled);
                  setState(() {});
                },
                active: sch.enabled,
              ),
              const SizedBox(width: 5),
              _mini(palette, 'TICK NOW', () async {
                await sch.tick();
                if (mounted) setState(() {});
              }),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 3),
            Text(
              'last: ${last.agentName.toLowerCase()} ${last.ageLabel} · '
              '${last.ok ? 'ok' : 'failed'} · ${sch.firedCount} total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.dim,
              ),
            ),
          ],
          if (armed == 0) ...[
            const SizedBox(height: 3),
            Text(
              'no agent is armed — set a task, then tap ⟳ AUTO ON on a card',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 8,
                color: palette.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fleetToolbar(
    StudioController studio,
    Palette palette,
    int count,
  ) {
    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Text(
            'AGENTS',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9.5,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: palette.mid,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 9,
              color: palette.dim,
            ),
          ),
          const SizedBox(width: 10),
          _mini(
            palette,
            'ALL',
            () => setState(() => _filter = 'ALL'),
            active: _filter == 'ALL',
          ),
          const SizedBox(width: 4),
          _mini(
            palette,
            'AUTO',
            () => setState(() => _filter = 'AUTO'),
            active: _filter == 'AUTO',
          ),
          const Spacer(),
          _mini(palette, '+ CRAFT', () => _craftDialog(studio, palette),
              active: true),
        ],
      ),
    );
  }

  Widget _emptyFleet(Palette palette) {
    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.all(16),
      child: Text(
        'No agents. Tap + CRAFT to make one.',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 10,
          color: palette.dim,
        ),
      ),
    );
  }

  // ── Agent card ─────────────────────────────────────────────────────────

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
    final lastLine =
        agent.transcript.isEmpty ? null : agent.transcript.last;
    final model = agent.piModel.isEmpty
        ? (provider?.model ?? 'default')
        : agent.piModel;

    return TermPanel(
      palette: palette,
      expand: false,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── identity row ───────────────────────────────────────────────
          Row(
            children: [
              Container(width: 3, height: 14, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  agent.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: agent.enabled ? palette.bright : palette.dim,
                  ),
                ),
              ),
              _stateTag(agent, palette),
              const SizedBox(width: 6),
              Text(
                agent.enabled ? '●' : '○',
                style: TextStyle(fontSize: 9, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // ── model + provider + run/reset/toggle ────────────────────────
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _modelSheet(studio, palette, agent),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: live ? palette.line : palette.warn,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '⌘ ',
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 9,
                            color: live ? palette.mid : palette.warn,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Mono',
                              fontSize: 8.5,
                              color: live ? palette.mid : palette.warn,
                            ),
                          ),
                        ),
                        Text(
                          '▾',
                          style: TextStyle(
                            fontFamily: 'Mono',
                            fontSize: 8,
                            color: palette.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _iconTap(
                palette,
                agent.busy ? '■' : '▶',
                agent.busy ? palette.err : palette.bright,
                () {
                  if (agent.busy) {
                    studio.cancelAgent(agent.id);
                  } else {
                    final task = _taskFor(agent);
                    studio.runAgent(agent.id, task);
                  }
                  setState(() {});
                },
                hint: agent.busy ? 'stop' : 'run',
              ),
              _iconTap(palette, '↺', palette.mid,
                  () => setState(() => studio.resetAgent(agent.id)),
                  hint: 'reset'),
              _iconTap(
                palette,
                agent.enabled ? '◉' : '○',
                palette.mid,
                () => setState(() => studio.toggleAgent(agent.id)),
                hint: 'enable',
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── provider binding ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  '${provider?.label ?? 'unbound'} · ${live ? 'LIVE' : 'OFFLINE'}'
                  ' · ${agent.toolCalls} tools · ${agent.tokensOut} tok',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8,
                    color: live ? palette.ok : palette.warn,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _bindSheet(studio, palette, agent),
                child: Text(
                  'BIND',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 7.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: palette.mid,
                  ),
                ),
              ),
            ],
          ),

          if (lastLine != null) ...[
            const SizedBox(height: 4),
            Text(
              '${lastLine.prefix}> ${_oneLine(lastLine.text, 140)}',
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
          const SizedBox(height: 6),
          _scheduleRow(studio, palette, agent),
        ],
      ),
    );
  }

  String _taskFor(AgentRuntime agent) {
    final t = agent.task.trim();
    if (t.isNotEmpty) return t;
    final b = _brief.text.trim();
    if (b.isNotEmpty) return b;
    return 'Review the current terminal state and report anything that needs '
        'attention, in three short lines.';
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
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  final newTask = agent.task.trim().isEmpty
                      ? 'Summarise the current state of the app in three lines.'
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
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                      fontSize: 7.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: armed ? palette.ok : palette.dim,
                    ),
                  ),
                ),
              ),
              _intervalStepper(studio, palette, agent),
              InkWell(
                onTap: () => _editTask(studio, palette, agent),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration:
                      BoxDecoration(border: Border.all(color: palette.line)),
                  child: Text(
                    agent.task.trim().isEmpty ? 'SET TASK' : 'EDIT TASK',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: palette.mid,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: agent.busy
                    ? null
                    : () async {
                        if (agent.task.trim().isEmpty) {
                          await _editTask(studio, palette, agent);
                          if (agent.task.trim().isEmpty) return;
                        }
                        await studio.runAgentNow(agent.id);
                        if (mounted) setState(() {});
                      },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: agent.busy ? palette.line : palette.bright,
                    ),
                    color: agent.busy
                        ? null
                        : palette.bright.withValues(alpha: 0.08),
                  ),
                  child: Text(
                    agent.busy ? 'RUNNING' : 'RUN NOW',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 7.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: agent.busy ? palette.dim : palette.bright,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (agent.task.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '⟳ ${_oneLine(agent.task, 160)}',
              maxLines: 2,
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
                    ? 'due now · ${agent.autoRuns} auto runs'
                    : 'next in ${_shortDuration(next)} · ${agent.autoRuns} auto runs')
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
    const stops = [1, 5, 15, 30, 60, 180, 360, 720, 1440];
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '−',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  color: palette.mid,
                ),
              ),
            ),
          ),
          Text(
            _shortMinutes(agent.everyMinutes),
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 7.5,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '+',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
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

  // ── Model picker ───────────────────────────────────────────────────────

  Future<void> _modelSheet(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.panel,
      isScrollControlled: true,
      builder: (ctx) => _ModelPickerSheet(
        palette: palette,
        studio: studio,
        current: agent.piModel.isEmpty ? studio.pi.activeModel : agent.piModel,
      ),
    );
    if (picked == null) return;
    agent.piModel = picked;
    studio.appLog.info(
      '${agent.name.toLowerCase()} model → $picked',
      scope: 'agents',
    );
    studio.bindAgentToPi(agent.id, model: picked);
    if (mounted) setState(() {});
  }

  Future<void> _bindSheet(
    StudioController studio,
    Palette palette,
    AgentRuntime agent,
  ) async {
    final llms = studio.providers.where((p) => p.kind == ProviderKind.llm);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.panel,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Text(
                'BIND ${agent.name} TO A PROVIDER',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: palette.bright,
                ),
              ),
            ),
            for (final p in llms)
              ListTile(
                dense: true,
                title: Text(
                  p.label,
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11,
                    color: p.ready ? palette.bright : palette.dim,
                  ),
                ),
                subtitle: Text(
                  '${p.ready ? p.maskedKey : 'no key'} · ${p.model}',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 8.5,
                    color: palette.dim,
                  ),
                ),
                trailing: p.id == agent.providerId
                    ? Icon(Icons.check, size: 14, color: palette.ok)
                    : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    studio.bindAgent(agent.id, picked);
    if (mounted) setState(() {});
  }

  // ── Craft / task dialogs ───────────────────────────────────────────────

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
              setState(() {});
            },
            child: Text('CREATE',
                style: TextStyle(
                    fontFamily: 'Mono', fontSize: 9, color: palette.bright)),
          ),
        ],
      ),
    );
    name.dispose();
    persona.dispose();
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
        labelStyle:
            TextStyle(fontFamily: 'Mono', fontSize: 9, color: palette.dim),
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
        shape: const RoundedRectangleBorder(),
        title: Text(
          'STANDING TASK · ${agent.name}',
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 11,
            letterSpacing: 1.1,
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

  // ── Run history ────────────────────────────────────────────────────────

  Widget _runHistory(StudioController studio, Palette palette) {
    final runs = studio.scheduler.history;
    final events = studio.feed;
    return TermPanel(
      palette: palette,
      expand: false,
      title: 'EVENT STREAM',
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      trailing: Text(
        '${runs.length} runs · ${events.length} events',
        style: TextStyle(
          fontFamily: 'Mono',
          fontSize: 8.5,
          color: palette.dim,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (runs.isEmpty && events.isEmpty)
            Text(
              'no agent activity yet — dispatch a brief or arm an agent',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 9.5,
                color: palette.dim,
              ),
            ),
          for (final r in runs.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${r.ok ? '✓' : '!'} ${r.agentName.toLowerCase()} · '
                '${r.ageLabel} · ${r.ok ? 'ok' : r.note}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: r.ok ? palette.ok : palette.err,
                ),
              ),
            ),
          for (final e in events.reversed.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${_eventGlyph(e.kind)} ${_oneLine(e.text, 140)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 8.5,
                  color: _eventColor(palette, e.kind),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _eventGlyph(AgentEventKind k) => switch (k) {
        AgentEventKind.thinking => '·',
        AgentEventKind.tool => '→',
        AgentEventKind.toolResult => '←',
        AgentEventKind.message => '»',
        AgentEventKind.done => '✓',
        AgentEventKind.warn => '!',
        AgentEventKind.info => 'i',
      };

  static Color _eventColor(Palette p, AgentEventKind k) => switch (k) {
        AgentEventKind.thinking => p.warn,
        AgentEventKind.tool => p.mid,
        AgentEventKind.toolResult => p.dim,
        AgentEventKind.message => p.bright,
        AgentEventKind.done => p.ok,
        AgentEventKind.warn => p.warn,
        AgentEventKind.info => p.dim,
      };

  String _oneLine(String s, int max) {
    final flat = s.replaceAll('\n', ' · ').trim();
    return flat.length > max ? '${flat.substring(0, max)}…' : flat;
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

  Widget _iconTap(
    Palette p,
    String glyph,
    Color color,
    VoidCallback onTap, {
    String? hint,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: p.line)),
        child: Text(
          glyph,
          style: TextStyle(fontFamily: 'Mono', fontSize: 11, color: color),
        ),
      ),
    );
  }

  Widget _mini(
    Palette palette,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: active ? palette.mid : palette.line),
          color: active ? palette.mid.withValues(alpha: 0.13) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.bright : palette.dim,
          ),
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

/// Searchable model list, backed by the live pi catalog.
///
/// The catalog is provider-seeded, so a key saved in KEYS shows up here on the
/// next frame without an app restart.
class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.palette,
    required this.studio,
    required this.current,
  });

  final Palette palette;
  final StudioController studio;
  final String current;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final TextEditingController _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final hits = widget.studio.pi.search(_query);
    final total = widget.studio.pi.models.length;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'MODEL · $total in catalog',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: p.bright,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TermKeyBar(
                palette: p,
                compact: true,
                cursor: TermCursor(
                  _q,
                  onComplete: (v) => v,
                  onSubmit: () {},
                ),
                extra: [
                  TermKey('REFRESH', () async {
                    await widget.studio.pi
                        .probeProviders(widget.studio.providers);
                    if (mounted) setState(() {});
                  }, hint: 'ask providers for /models'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _q,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11,
                  color: p.bright,
                ),
                cursorColor: p.bright,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon:
                      Icon(Icons.search, size: 14, color: p.dim),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 26, minHeight: 0),
                  hintText: 'search models — try "sonnet", "free", "qwen"',
                  hintStyle:
                      TextStyle(fontFamily: 'Mono', fontSize: 10, color: p.dim),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: p.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: p.mid),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: hits.isEmpty
                  ? Center(
                      child: Text(
                        total == 0
                            ? 'catalog empty — add an LLM key in KEYS'
                            : 'no model matching "$_query"',
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 10,
                          color: p.dim,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: p.line.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (ctx, i) {
                        final m = hits[i];
                        final sel = m.id == widget.current;
                        return InkWell(
                          onTap: () => Navigator.pop(ctx, m.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Mono',
                                          fontSize: 10.5,
                                          color: sel ? p.bright : p.mid,
                                          fontWeight: sel
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                      Text(
                                        '${m.providerId} · ctx ${m.contextLabel}'
                                        '${m.free ? ' · free' : ''}'
                                        '${m.live ? ' · live' : ''}',
                                        style: TextStyle(
                                          fontFamily: 'Mono',
                                          fontSize: 8,
                                          color: p.dim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (sel)
                                  Icon(Icons.check, size: 14, color: p.ok),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
