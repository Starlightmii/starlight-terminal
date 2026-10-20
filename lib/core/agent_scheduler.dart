import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_runtime.dart';

/// One recorded firing, for the AGENTS panel's run history.
@immutable
class ScheduledRun {
  const ScheduledRun({
    required this.agentId,
    required this.agentName,
    required this.task,
    required this.at,
    required this.ok,
    this.note = '',
  });

  final String agentId;
  final String agentName;
  final String task;
  final DateTime at;
  final bool ok;
  final String note;

  String get ageLabel {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// Drives autonomous agent runs.
///
/// A single 20-second heartbeat scans the fleet and fires any agent whose
/// `autoRun` interval has elapsed. One ticker for the whole fleet, rather than
/// a `Timer` per agent, keeps the cost flat as the fleet grows and makes the
/// "due" rule trivial to reason about:
///
///     due  ==  autoRun && task.isNotEmpty && (now - (lastRun ?? epoch) >= every)
///
/// Runs are sequential, never overlapping: an agent already busy is skipped to
/// the next tick instead of being double-run.
class AgentScheduler extends ChangeNotifier {
  AgentScheduler({
    required this.agentsProvider,
    required this.runner,
    this.heartbeat = const Duration(seconds: 20),
    this.maxHistory = 40,
  });

  /// The live fleet. Injected rather than owned, so the controller stays the
  /// single source of truth.
  final List<AgentRuntime> Function() agentsProvider;

  /// Executes one agent turn. Returns when the turn finishes.
  final Future<void> Function(AgentRuntime agent, String task) runner;

  final Duration heartbeat;
  final int maxHistory;

  Timer? _timer;
  bool _enabled = true;
  bool _firing = false;

  final List<ScheduledRun> _history = <ScheduledRun>[];

  /// Newest first.
  List<ScheduledRun> get history => List<ScheduledRun>.unmodifiable(_history);

  bool get enabled => _enabled;

  int get firedCount => _history.length;

  /// How many agents are currently armed.
  int get armedCount =>
      agentsProvider().where((a) => a.autoRun && a.task.trim().isNotEmpty).length;

  void start() {
    _timer?.cancel();
    if (!_enabled) return;
    _timer = Timer.periodic(heartbeat, (_) => unawaited(tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setEnabled(bool on) {
    if (_enabled == on) return;
    _enabled = on;
    if (on) {
      start();
    } else {
      stop();
    }
    notifyListeners();
  }

  /// True when this agent is due right now.
  bool isDue(AgentRuntime a, {DateTime? now}) {
    if (!a.autoRun || !a.enabled) return false;
    if (a.task.trim().isEmpty) return false;
    if (a.busy) return false;
    final t = now ?? DateTime.now();
    final last = a.lastAutoRun;
    if (last == null) return true;
    final every = Duration(minutes: a.everyMinutes.clamp(1, 24 * 60));
    return t.difference(last) >= every;
  }

  Duration? nextDueIn(AgentRuntime a) {
    if (!a.autoRun || a.task.trim().isEmpty) return null;
    final last = a.lastAutoRun;
    if (last == null) return Duration.zero;
    final every = Duration(minutes: a.everyMinutes.clamp(1, 24 * 60));
    final left = every - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  /// Scans the fleet and runs whatever is due. Safe to call at any time;
  /// re-entrant calls are ignored while a sweep is in flight.
  Future<void> tick() async {
    if (!_enabled || _firing) return;
    _firing = true;
    try {
      final due = agentsProvider().where((a) => isDue(a)).toList();
      for (final agent in due) {
        if (!_enabled) break;
        // Re-check: a previous run in this sweep may have taken a while.
        if (!isDue(agent)) continue;
        agent.lastAutoRun = DateTime.now();
        agent.autoRuns += 1;
        notifyListeners();
        var ok = true;
        var note = '';
        try {
          await runner(agent, agent.task.trim());
        } catch (e) {
          ok = false;
          note = '$e';
        }
        _remember(ScheduledRun(
          agentId: agent.id,
          agentName: agent.name,
          task: agent.task.trim(),
          at: DateTime.now(),
          ok: ok,
          note: note,
        ));
      }
    } finally {
      _firing = false;
      notifyListeners();
    }
  }

  /// Fire one agent immediately, regardless of schedule.
  Future<void> runNow(AgentRuntime agent, {String? task}) async {
    final t = (task ?? agent.task).trim();
    if (t.isEmpty) return;
    agent.lastAutoRun = DateTime.now();
    agent.autoRuns += 1;
    notifyListeners();
    var ok = true;
    var note = '';
    try {
      await runner(agent, t);
    } catch (e) {
      ok = false;
      note = '$e';
    }
    _remember(ScheduledRun(
      agentId: agent.id,
      agentName: agent.name,
      task: t,
      at: DateTime.now(),
      ok: ok,
      note: note,
    ));
  }

  void _remember(ScheduledRun r) {
    _history.insert(0, r);
    if (_history.length > maxHistory) _history.removeLast();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
