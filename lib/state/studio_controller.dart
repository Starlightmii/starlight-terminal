import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent_runtime.dart';
import '../core/agent_scheduler.dart';
import '../core/app_log.dart';
import '../core/effects.dart';
import '../core/memory.dart';
import '../core/palette.dart';
import '../core/model_client.dart';
import '../core/pi_core.dart';
import '../core/users.dart';
import '../core/vfs.dart';
import '../core/providers.dart';
import '../core/session_store.dart';
import 'terminal_controller.dart';

/// How a multi-agent run is coordinated.
enum OrchestrationMode {
  /// Every enabled agent gets the same task, in parallel.
  broadcast,

  /// Agents run one after another, each seeing the previous summary.
  pipeline,

  /// One coordinator expands the task and dispatches per-agent subtasks.
  dispatch,
}

/// Owns everything that is not "the sky": provider keys, the agent fleet,
/// and the background effect stack.
class StudioController extends ChangeNotifier implements CommandBridge {
  StudioController({required this.terminal});

  final TerminalController terminal;

  // ── Providers / keys ───────────────────────────────────────────────────
  List<Provider> _providers = List<Provider>.from(ProviderPresets.all);
  List<Provider> get providers => List.unmodifiable(_providers);

  Provider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Provider> get readyProviders =>
      _providers.where((p) => p.ready && p.looksPlausible).toList();

  List<Provider> ofKind(ProviderKind k) =>
      _providers.where((p) => p.kind == k).toList();

  int get configuredCount => readyProviders.length;

  // ── Agents ─────────────────────────────────────────────────────────────
  final List<AgentRuntime> _agents = AgentPresets.build();
  List<AgentRuntime> get agents => List.unmodifiable(_agents);

  AgentRuntime? agentById(String id) {
    for (final a in _agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  AgentLoop? _loop;

  /// A flat, tail-able event feed across every agent.
  final List<AgentEvent> _feed = <AgentEvent>[];
  List<AgentEvent> get feed => List.unmodifiable(_feed);

  String? _feedAuthor;
  String? get feedAuthor => _feedAuthor;

  bool _orchestrating = false;
  bool get orchestrating => _orchestrating;

  OrchestrationMode _mode = OrchestrationMode.broadcast;
  OrchestrationMode get mode => _mode;

  // ── Effects ────────────────────────────────────────────────────────────
  EffectParams _effects = const EffectParams();
  EffectParams get effects => _effects;

  // ── Pi agent core (native; no HTTP broker) ─────────────────────────────
  //
  // Earlier builds drove a `pi` CLI over a loopback HTTP bridge. That cannot
  // work on a phone — 127.0.0.1 on the device is the device, and pi needs
  // Node 22.19+ which Android cannot host. pi is now a managed component
  // (version, manifest, real npm update checks) whose work is executed by the
  // app itself against the operator's keys.
  final PiCore pi = PiCore();
  final ModelClient models = ModelClient();
  final Vfs fs = Vfs();
  final UserStore users = UserStore();

  /// Ready LLM providers, best first — what the agent actually runs on.
  List<Provider> get agentProviders =>
      readyProviders.where((p) => p.kind == ProviderKind.llm).toList();

  Provider? get agentProvider =>
      agentProviders.isEmpty ? null : agentProviders.first;

  bool get piOnline => pi.state == PiInstallState.installed;

  /// The pi-backed turn used by [AgentLoop].
  ///
  /// This is the whole point of the rewrite: an agent step is a direct model
  /// call with the operator's key, streamed into the transcript and the log.
  /// No bridge, no loopback port, nothing that only exists on a desktop.
  Future<void> _runPiTurn(
    AgentRuntime agent,
    String task,
    void Function(AgentRuntime agent, AgentEvent event) onEvent,
  ) async {
    final provider = agentProvider;
    if (provider == null) {
      onEvent(agent, AgentEvent(
        kind: AgentEventKind.warn,
        text: 'no usable LLM key — add one in KEYS to run agents',
      ));
      agent.setState(AgentRunState.error, 'unconfigured');
      return;
    }

    agent.setState(AgentRunState.thinking, 'pi · ${agent.name.toLowerCase()}');
    onEvent(agent, AgentEvent(
      kind: AgentEventKind.info,
      text: 'pi ${pi.installedVersion} → ${provider.id} · ${agent.piModel.isEmpty ? 'default model' : agent.piModel}',
    ));

    final system = StringBuffer(
      'You are ${agent.name}, ${agent.persona}. '
      'Be concise and concrete. Prefer short paragraphs and plain text.',
    );
    if (agent.persona.trim().isNotEmpty) {
      system.write('\n\n${agent.persona.trim()}');
    }

    final history = <Map<String, String>>[];
    for (final line in agent.transcript.length > 12
        ? agent.transcript.sublist(agent.transcript.length - 12)
        : agent.transcript) {
      if (line.role == AgentRole.assistant) {
        history.add({'role': 'assistant', 'content': line.text});
      }
    }
    history.add({'role': 'user', 'content': task});

    final buf = StringBuffer();
    try {
      await for (final c in models.stream(
        provider: provider,
        messages: history,
        model: agent.piModel.isEmpty ? null : agent.piModel,
        system: system.toString(),
      )) {
        switch (c.kind) {
          case ChunkKind.text:
            buf.write(c.text);
          case ChunkKind.thinking:
            onEvent(agent, AgentEvent(kind: AgentEventKind.thinking, text: c.text));
          case ChunkKind.error:
            onEvent(agent, AgentEvent(kind: AgentEventKind.warn, text: c.text));
            appLog.error(c.text, scope: agent.name.toLowerCase());
            agent.setState(AgentRunState.error, 'pi error');
            return;
          case ChunkKind.tool:
          case ChunkKind.done:
            break;
        }
      }
    } catch (e) {
      onEvent(agent, AgentEvent(kind: AgentEventKind.warn, text: '$e'));
      agent.setState(AgentRunState.error, 'pi error');
      return;
    }

    final reply = buf.toString().trim();
    if (reply.isEmpty) {
      agent.setState(AgentRunState.error, 'empty reply');
      return;
    }
    onEvent(agent, AgentEvent(kind: AgentEventKind.message, text: reply));
    agent.setState(AgentRunState.idle, 'done');
  }

  /// Executes a shell command against [fs]. Returns null when the command is
  /// not a shell builtin, so the terminal can fall back to its own grammar.
  ///
  /// This is what makes CONSOLE a terminal rather than a command palette:
  /// there is a real working directory, real files, and real pipes-of-one.
  String? shellExec(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return '';
    final parts = line.split(RegExp(r'\s+'));
    final cmd = parts.first;
    final args = parts.skip(1).toList();

    switch (cmd) {
      case 'pwd':
        return fs.cwd;
      case 'cd':
        if (args.isEmpty) {
          fs.cd('/home/user');
          return '';
        }
        if (!fs.cd(args.first)) return 'cd: no such directory: ${args.first}';
        return '';
      case 'ls':
        final entries = fs.list(args.isEmpty ? '.' : args.first);
        if (entries == null) return 'ls: not a directory: ${args.isEmpty ? '.' : args.first}';
        if (entries.isEmpty) return '';
        return entries
            .map((e) => e.value ? '${e.key}/' : e.key)
            .join('   ');
      case 'cat':
        if (args.isEmpty) return 'usage: cat <file>';
        final body = fs.read(args.first);
        return body ?? 'cat: no such file: ${args.first}';
      case 'mkdir':
        if (args.isEmpty) return 'usage: mkdir <dir>';
        return fs.mkdir(args.first) ? '' : 'mkdir: exists: ${args.first}';
      case 'touch':
        if (args.isEmpty) return 'usage: touch <file>';
        fs.write(args.first, '');
        return '';
      case 'rm':
        if (args.isEmpty) return 'usage: rm <path>';
        return fs.remove(args.first) ? '' : 'rm: no such path: ${args.first}';
      case 'echo':
        final text = args.join(' ');
        // `echo text > file` writes through.
        final gt = text.indexOf('>');
        if (gt >= 0) {
          final target = text.substring(gt + 1).trim();
          if (target.isNotEmpty) {
            fs.write(target, text.substring(0, gt).trim());
            return '';
          }
        }
        return text;
      case 'df':
        return 'fs      files\n${fs.fileCount.toString().padLeft(6)} ${fs.prompt}';
      case 'whoami':
        return 'operator';
      case 'uname':
        return 'Starlight Terminal · ${pi.statusLabel}';
      case 'pi':
        return _piCmd(args);
      default:
        return null; // not a builtin
    }
  }

  String _piCmd(List<String> args) {
    final sub = args.isEmpty ? 'status' : args.first;
    switch (sub) {
      case 'status':
        return 'state     ${pi.statusLabel}\n'
            'installed ${pi.installedVersion.isEmpty ? '—' : pi.installedVersion}\n'
            'model     ${pi.activeModel.isEmpty ? '—' : pi.activeModel}\n'
            'provider  ${agentProvider?.id ?? 'none'}';
      case 'models':
        return pi.models.isEmpty
            ? 'no models — run `pi install`'
            : pi.models
                .map((m) => '${m.id}  (${m.vendor})')
                .join('\n');
      case 'help':
        return 'pi — agent core\n'
            '  pi status | models | install | update';
      case 'install':
        unawaited(pi.install());
        return 'installing pi…';
      case 'update':
        unawaited(pi.update().then(
              (m) => appLog.info(m, scope: 'pi'),
            ));
        return 'checking registry…';
      default:
        return 'pi: unknown subcommand "$sub"';
    }
  }

  /// Bind an agent to the pi backend (or back to the offline planner).
  void bindAgentToPi(String agentId, {bool enabled = true, String? model}) {
    final a = agentById(agentId);
    if (a == null) return;
    a.engine = enabled ? AgentEngine.pi : AgentEngine.local;
    if (model != null) a.piModel = model;
    _persistAgents();
    _notify();
  }

  /// Maps a vault provider to the provider id Pi uses internally.
  static String piProviderId(Provider p) {
    switch (p.id) {
      case 'openai':
        return 'openai';
      case 'anthropic':
        return 'anthropic';
      case 'gemini':
        return 'google';
      case 'zai':
        return 'zai';
      case 'deepseek':
        return 'deepseek';
      case 'mistral':
        return 'mistral';
      case 'groq':
        return 'groq';
      case 'openrouter':
        return 'openrouter';
      default:
        return p.id;
    }
  }

  // ── Memory, sessions, logs, scheduling ─────────────────────────────────

  /// Everything the operator has learned, across every chat surface.
  final MemoryStore memory = MemoryStore();

  /// Every conversation: pi, bots and autonomous jobs.
  late final SessionStore sessions = SessionStore(memories: memory);

  /// The app-wide log tail shown by the LOG tab.
  final AppLog appLog = AppLog();

  late final AgentScheduler scheduler = AgentScheduler(
    agentsProvider: () => _agents,
    runner: (agent, task) => runScheduled(agent, task),
  );

  /// Mirror agent transcript traffic into the log and the active job session.
  void _mirrorAgentEvent(AgentRuntime agent, AgentEvent event) {
    switch (event.kind) {
      case AgentEventKind.tool:
        appLog.tool(event.text, scope: agent.name.toLowerCase());
      case AgentEventKind.warn:
        appLog.warn(event.text, scope: agent.name.toLowerCase());
      case AgentEventKind.info:
        appLog.info(event.text, scope: agent.name.toLowerCase());
      case AgentEventKind.done:
        appLog.info('done · ${event.text}', scope: agent.name.toLowerCase());
      case AgentEventKind.message:
      case AgentEventKind.toolResult:
        appLog.info(event.text, scope: agent.name.toLowerCase());
      case AgentEventKind.thinking:
        appLog.debug(event.text, scope: agent.name.toLowerCase());
    }
  }

  /// Run a scheduled agent and file the result as a job session.
  Future<void> runScheduled(AgentRuntime agent, String task) async {
    final s = sessions.create(
      kind: SessionKind.job,
      title: '${agent.name.toLowerCase()} · ${task.split('\n').first}',
      agentId: agent.id,
      tags: const ['scheduled'],
    );
    sessions.appendMessage(s.id, SessionMessage(
      role: 'you',
      text: task,
      at: DateTime.now(),
    ));
    appLog.info('scheduled run: ${agent.name}', scope: 'scheduler');
    await runAgent(agent.id, task);
    final tail = agent.transcript.isEmpty ? null : agent.transcript.last;
    if (tail != null) {
      sessions.appendMessage(
        s.id,
        SessionMessage(
          role: 'agent',
          text: tail.text,
          at: DateTime.now(),
          isError: agent.state == AgentRunState.error,
        ),
        remember: true,
      );
    }
    sessions.appendMessage(s.id, SessionMessage(
      role: 'sys',
      text: 'run finished · ${agent.state.name}',
      at: DateTime.now(),
    ));
  }

  /// Remove every persisted artifact this app owns.
  Future<void> wipeAllData() async {
    sessions.clearAll();
    memory.clear();
    appLog.clear();
    scheduler.clearHistory();
    _prefs?.remove(_kSessions);
    _prefs?.remove(_kMemories);
    appLog.warn('all local data wiped', scope: 'system');
    _notify();
  }

  // ── Internals ──────────────────────────────────────────────────────────
  SharedPreferences? _prefs;
  bool _disposed = false;
  int _customSeq = 0;

  static const _kProviders = 'starlight.providers.v1';
  static const _kAgents = 'starlight.agents.v1';
  static const _kEffects = 'starlight.effects.v1';
  static const _kSessions = 'starlight.sessions.v1';
  static const _kMemories = 'starlight.memories.v1';
  static const _kUsers = 'starlight.users.v1';

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> start() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _restoreProviders();
      _restoreAgents();
      _restoreEffects();
      _restoreJournal();
    } catch (_) {
      // Persistence is optional; the studio works in-memory regardless.
    }
    _installLoop();
    // Let the console drive agents, keys and effects from the prompt.
    terminal.bridge = this;
    // Attach the real Pi runtime. Failure only disables Pi-backed agents; the
    // local loop and the whole TUI keep working.
    pi.addListener(_notify);

    _loop!.piRunner = _runPiTurn;
    memory.addListener(_notify);
    sessions.addListener(_notify);
    appLog.info('studio online · ${_agents.length} agents', scope: 'system');
    // Autonomous runs: one heartbeat for the fleet.
    scheduler.start();
    // Provision the agent core on first boot so the terminal has a `pi` to run.
    if (pi.state != PiInstallState.installed) unawaited(pi.install());
    _notify();
  }

  /// Persist sessions and memories. Called on a debounce from the listeners.
  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveJournal);
  }

  void _saveJournal() {
    final p = _prefs;
    if (p == null) return;
    try {
      p.setString(_kSessions, sessions.encode());
      p.setString(_kMemories, memory.encode());
      p.setString(_kUsers, users.encode());
    } catch (e) {
      appLog.error('persist failed: $e', scope: 'system');
    }
  }

  void _restoreJournal() {
    final p = _prefs;
    if (p == null) return;
    memory.loadEncoded(p.getString(_kMemories) ?? '');
    users.loadEncoded(p.getString(_kUsers) ?? '');
    sessions.loadEncoded(p.getString(_kSessions));
    sessions.addListener(_scheduleSave);
    memory.addListener(_scheduleSave);
  }

  void _installLoop() {
    _loop = AgentLoop(
      context: AgentContext(
        stars: terminal.stars,
        latitude: terminal.latitude,
        longitude: terminal.longitude,
        lstDegrees: terminal.lstDegrees,
        now: terminal.observationTime,
        siteName: terminal.siteName,
        onNote: terminal.addNote,
        onPalette: (name) => terminal.setPalette(Palette.byName(name)),
        onTimeShift: terminal.shiftTime,
        onEffect: (id) => setEffectByName(id),
      ),
      providerFor: byId,
      onEvent: _onAgentEvent,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveJournal();
    scheduler.dispose();
    pi.removeListener(_notify);
    pi.dispose();
    models.dispose();
    fs.dispose();
    users.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Provider mutations ─────────────────────────────────────────────────

  void setKey(String providerId, String key) {
    final i = _providers.indexWhere((p) => p.id == providerId);
    if (i < 0) return;
    _providers[i] = _providers[i].copyWith(apiKey: key.trim());
    _persistProviders();
    _notify();
  }

  void setModel(String providerId, String model) {
    final i = _providers.indexWhere((p) => p.id == providerId);
    if (i < 0) return;
    _providers[i] = _providers[i].copyWith(model: model.trim());
    _persistProviders();
    _notify();
  }

  void setBaseUrl(String providerId, String url) {
    final i = _providers.indexWhere((p) => p.id == providerId);
    if (i < 0) return;
    _providers[i] = _providers[i].copyWith(baseUrl: url.trim());
    _persistProviders();
    _notify();
  }

  void toggleProvider(String providerId) {
    final i = _providers.indexWhere((p) => p.id == providerId);
    if (i < 0) return;
    _providers[i] = _providers[i].copyWith(enabled: !_providers[i].enabled);
    _persistProviders();
    _notify();
  }

  void clearKey(String providerId) => setKey(providerId, '');

  /// Add a custom OpenAI-compatible endpoint.
  Provider addCustomProvider({
    required String label,
    required String baseUrl,
    required String model,
    ProviderKind kind = ProviderKind.llm,
    String apiKey = '',
  }) {
    _customSeq++;
    final p = Provider(
      id: 'custom-$_customSeq',
      label: label.isEmpty ? 'Custom $_customSeq' : label,
      kind: kind,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      notes: 'User-defined OpenAI-compatible endpoint.',
    );
    _providers.add(p);
    _persistProviders();
    _notify();
    return p;
  }

  void removeProvider(String id) {
    _providers.removeWhere((p) => p.id == id && !p.isPreset);
    _persistProviders();
    _notify();
  }

  // ── Agent mutations ────────────────────────────────────────────────────

  void bindAgent(String agentId, String providerId) {
    final a = agentById(agentId);
    if (a == null) return;
    // Mutate in place: replacing the object would throw away the transcript,
    // the Pi binding and the schedule the operator configured.
    a.providerId = providerId;
    _persistAgents();
    _notify();
  }

  /// Arm or disarm an agent's autonomous schedule.
  void setAgentSchedule(
    String agentId, {
    bool? autoRun,
    int? everyMinutes,
    String? task,
  }) {
    final a = agentById(agentId);
    if (a == null) return;
    if (autoRun != null) a.autoRun = autoRun;
    if (everyMinutes != null) a.everyMinutes = everyMinutes.clamp(1, 1440);
    if (task != null) a.task = task;
    appLog.info(
      '${a.name.toLowerCase()} schedule '
      '${a.autoRun ? 'armed every ${a.everyMinutes}m' : 'disarmed'}',
      scope: 'scheduler',
    );
    _persistAgents();
    _notify();
  }

  /// Fire one agent right now, outside its schedule.
  Future<void> runAgentNow(String agentId, {String? task}) async {
    final a = agentById(agentId);
    if (a == null) return;
    await scheduler.runNow(a, task: task);
    _notify();
  }

  void toggleAgent(String agentId) {
    final a = agentById(agentId);
    if (a == null) return;
    a.enabled = !a.enabled;
    _persistAgents();
    _notify();
  }

  void addAgent({required String name, required String persona}) {
    final id = 'agent-${DateTime.now().millisecondsSinceEpoch % 100000}';
    _agents.add(AgentRuntime(
      id: id,
      name: name.toUpperCase(),
      persona: persona,
      providerId: readyProviders.isEmpty ? 'groq' : readyProviders.first.id,
      colorIndex: _agents.length % 4,
    ));
    _persistAgents();
    _notify();
  }

  void removeAgent(String id) {
    _agents.removeWhere((a) => a.id == id);
    _persistAgents();
    _notify();
  }

  void resetAgent(String id) {
    agentById(id)?.reset();
    _notify();
  }

  // ── Running ────────────────────────────────────────────────────────────

  void _onAgentEvent(AgentRuntime agent, AgentEvent event) {
    _feedAuthor = agent.name;
    _feed.add(event);
    if (_feed.length > 200) _feed.removeRange(0, _feed.length - 200);
    _mirrorAgentEvent(agent, event);
    _notify();
  }

  /// Run a task on a single agent.
  Future<void> runAgent(String agentId, String task) async {
    final agent = agentById(agentId);
    final loop = _loop;
    if (agent == null || loop == null || task.trim().isEmpty) return;
    appLog.info(task, scope: agent.name.toLowerCase());
    await loop.run(agent, task.trim());
    _notify();
  }

  void cancelAgent(String agentId) {
    _loop?.cancel(agentId);
    _notify();
  }

  void setMode(OrchestrationMode m) {
    _mode = m;
    _notify();
  }

  /// Run a task across every enabled agent according to [mode].
  Future<void> dispatchFleet(String task, {OrchestrationMode? mode}) async {
    if (_orchestrating || task.trim().isEmpty) return;
    final loop = _loop;
    if (loop == null) return;

    final active = _agents.where((a) => a.enabled).toList();
    if (active.isEmpty) return;

    _orchestrating = true;
    if (mode != null) _mode = mode;
    _notify();

    try {
      switch (_mode) {
        case OrchestrationMode.broadcast:
          // All agents work the same brief at once.
          await Future.wait(
            active.map((a) => loop.run(a, task.trim(), maxTurns: 4)),
          );
        case OrchestrationMode.pipeline:
          // Each agent starts from the previous one's last message.
          var carry = '';
          for (final a in active) {
            final brief = carry.isEmpty
                ? task.trim()
                : '${task.trim()}\n\nPrevious agent (${a.name}) said:\n$carry';
            await loop.run(a, brief, maxTurns: 4);
            final last = a.transcript.isEmpty ? '' : a.transcript.last.text;
            carry = last.length > 400 ? last.substring(0, 400) : last;
          }
        case OrchestrationMode.dispatch:
          // Split the brief into a job per agent, then run them concurrently.
          final jobs = _dispatch(task.trim(), active);
          await Future.wait([
            for (var i = 0; i < active.length; i++)
              loop.run(active[i], jobs[i], maxTurns: 4),
          ]);
      }
    } finally {
      _orchestrating = false;
      _notify();
    }
  }

  /// Split one brief into per-agent jobs by matching persona keywords.
  List<String> _dispatch(String task, List<AgentRuntime> agents) {
    final sky = _query(task, const [
      'sky', 'visible', 'see', 'look', 'up', 'brightest', 'tonight'
    ]);
    final coords = _query(task, const [
      'where', 'coordinate', 'ra', 'dec', 'position', 'find', 'locate'
    ]);
    final look = _query(task, const [
      'theme', 'palette', 'effect', 'colour', 'color', 'look', 'style'
    ]);

    return agents.map((a) {
      switch (a.id) {
        case 'surveyor':
          return 'Report the visible sky.${sky ? ' Focus on what is worth seeing now.' : ''} $task';
        case 'navigator':
          return 'Resolve coordinates and positions.${coords ? ' Give where to look.' : ''} $task';
        case 'scribe':
          return 'Record the outcome of this session in the log. $task';
        case 'curator':
          return 'Adjust the terminal look for this session.${look ? ' Change palette or effect.' : ''} $task';
        default:
          return task;
      }
    }).toList();
  }

  bool _query(String task, List<String> words) {
    final q = task.toLowerCase();
    return words.any(q.contains);
  }

  // ── Effects ────────────────────────────────────────────────────────────

  void setEffects(EffectParams p) {
    _effects = p;
    _persistEffects();
    _notify();
  }

  void setEffectKind(EffectKind kind) => setEffects(_effects.copyWith(kind: kind));

  void setEffectByName(String name) {
    final n = name.trim().toLowerCase();
    for (final k in EffectKind.values) {
      if (k.name == n) {
        setEffectKind(k);
        return;
      }
    }
  }

  void randomiseEffects() {
    final r = math.Random();
    setEffects(EffectParams(
      kind: EffectKind.values[r.nextInt(EffectKind.values.length)],
      intensity: 0.35 + r.nextDouble() * 0.55,
      speed: 0.4 + r.nextDouble() * 1.8,
      density: 0.25 + r.nextDouble() * 0.7,
      scale: 0.6 + r.nextDouble() * 1.2,
      chroma: r.nextDouble(),
      grain: r.nextDouble() * 0.5,
    ));
  }

  void resetEffects() => setEffects(const EffectParams());

  // ── CommandBridge ──────────────────────────────────────────────────────

  @override
  List<({String id, String name, bool enabled, String provider, String state})>
      agentSummary() {
    return _agents.map((a) {
      final stateLabel = switch (a.state) {
        AgentRunState.idle => 'idle',
        AgentRunState.thinking => 'thinking',
        AgentRunState.toolCall => 'tool',
        AgentRunState.done => 'done',
        AgentRunState.error => 'error',
        AgentRunState.cancelled => 'stopped',
      };
      return (
        id: a.id,
        name: a.name,
        enabled: a.enabled,
        provider: byId(a.providerId)?.label ?? 'unbound',
        state: stateLabel,
      );
    }).toList();
  }

  @override
  void runAgentTask(String agentId, String task) {
    // Fire and forget: the console prints its own acknowledgement and the
    // AGENTS panel shows live progress.
    unawaited(runAgent(agentId, task));
  }

  @override
  void runFleet(String task) {
    if (task.trim().isEmpty) return;
    unawaited(dispatchFleet(task));
  }

  @override
  List<({String id, String label, String kind, bool ready, String masked})>
      providerSummary() {
    return _providers
        .map((p) => (
              id: p.id,
              label: p.label,
              kind: p.kindLabel,
              ready: p.ready && p.looksPlausible,
              masked: p.maskedKey,
            ))
        .toList();
  }

  @override
  void setProviderKey(String providerId, String key) => setKey(providerId, key);

  @override
  int get configuredKeys => configuredCount;

  @override
  List<String> effectNames() =>
      EffectKind.values.map((k) => k.name).toList();

  @override
  String currentEffect() => _effects.kind.name;

  @override
  void setEffect(String name) => setEffectByName(name);

  @override
  void randomiseEffect() => randomiseEffects();

  // ── Persistence ────────────────────────────────────────────────────────

  void _restoreProviders() {
    final raw = _prefs?.getString(_kProviders);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final stored = list.map(Provider.fromJson).toList();
      // Merge: keep any preset the stored data does not know about.
      final ids = stored.map((p) => p.id).toSet();
      final merged = <Provider>[
        ...stored,
        ...ProviderPresets.all.where((p) => !ids.contains(p.id)),
      ];
      _providers = merged;
      // Make sure custom ids keep incrementing past restored ones.
      for (final p in _providers) {
        if (p.id.startsWith('custom-')) {
          final n = int.tryParse(p.id.split('-').last) ?? 0;
          if (n > _customSeq) _customSeq = n;
        }
      }
    } catch (_) {
      // Corrupt payload — fall back to presets.
    }
  }

  void _restoreAgents() {
    final raw = _prefs?.getString(_kAgents);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;
      final restored = list.map(AgentRuntime.fromJson).toList();
      _agents
        ..clear()
        ..addAll(restored);
    } catch (_) {/* keep presets */}
  }

  void _restoreEffects() {
    final raw = _prefs?.getString(_kEffects);
    if (raw == null) return;
    try {
      _effects = EffectParams.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {/* keep default */}
  }

  Future<void> _persistProviders() async {
    try {
      await _prefs?.setString(
        _kProviders,
        jsonEncode(_providers.map((p) => p.toJson()).toList()),
      );
    } catch (_) {/* ignore */}
  }

  Future<void> _persistAgents() async {
    try {
      await _prefs?.setString(
        _kAgents,
        jsonEncode(_agents.map((a) => a.toJson()).toList()),
      );
    } catch (_) {/* ignore */}
  }

  Future<void> _persistEffects() async {
    try {
      await _prefs?.setString(_kEffects, jsonEncode(_effects.toJson()));
    } catch (_) {/* ignore */}
  }
}
