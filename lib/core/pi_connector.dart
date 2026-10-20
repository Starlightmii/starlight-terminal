import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_runtime.dart';
import 'pi_bridge.dart';

/// Where the bridge listens by default inside the sandbox.
///
/// Override per environment with `--dart-define=PI_BRIDGE_URL=...`; the value
/// is also editable at runtime from the PI panel.
const String kDefaultPiBridgeUrl = String.fromEnvironment(
  'PI_BRIDGE_URL',
  defaultValue: 'http://127.0.0.1:5077',
);

/// Connects the agent fleet to the genuinely installed Pi CLI.
///
/// Owns the bridge session, translates Pi's event records into the terminal's
/// event feed, and drives the auto-update path (`pi update`, model catalog
/// refresh, version probe).
class PiConnector extends ChangeNotifier {
  PiConnector({String baseUrl = kDefaultPiBridgeUrl})
      : _baseUrl = baseUrl,
        _client = PiBridgeClient(baseUrl: baseUrl);

  String _baseUrl;
  PiBridgeClient _client;

  String get baseUrl => _baseUrl;

  PiStatus _status = PiStatus.offline;
  PiStatus get status => _status;

  PiUpdateCheck? _update;
  PiUpdateCheck? get update => _update;

  List<PiModel> _models = const [];
  List<PiModel> get models => _models;

  String? _lastError;
  String? get lastError => _lastError;

  bool _busy = false;
  bool get busy => _busy;

  String _activity = '';
  String get activity => _activity;

  /// Last successful update/model refresh, for the panel's footer.
  DateTime? lastCatalogRefresh;
  DateTime? lastUpdateRun;

  /// Auto-update defaults: check on connect, then every 6 hours. Catalog
  /// refreshes are cheap and always run before a Pi-backed turn if stale.
  bool autoUpdate = true;
  Duration autoUpdateInterval = const Duration(hours: 6);
  Timer? _autoTimer;

  final String _sessionId = 'starlight-fleet';
  String get sessionId => _sessionId;
  bool _sessionOpen = false;
  bool get sessionOpen => _sessionOpen;

  bool get connected => _status.reachable && _status.installed != null;

  /// `provider/model` the operator picked for the interactive terminal.
  /// Empty means "let pi use whatever it defaults to".
  String _selectedModel = '';
  String get selectedModel => _selectedModel;

  /// Pin a model on the Pi side and remember it for the next session.
  Future<void> selectModel(String qualifiedId) async {
    final id = qualifiedId.trim();
    if (id.isEmpty) return;
    _selectedModel = id;
    notifyListeners();
    if (!connected) return;
    try {
      await _ensureSession();
      final slash = id.indexOf('/');
      final provider = slash < 0 ? '' : id.substring(0, slash);
      final modelId = slash < 0 ? id : id.substring(slash + 1);
      await _client.setModel(_sessionId, provider: provider, modelId: modelId);
    } catch (e) {
      _lastError = _short(e);
      notifyListeners();
    }
  }

  List<String> get providers => _status.providers;

  /// Providers for which Pi has a credential. Matches Pi's own provider ids.
  bool hasCredential(String provider) => _status.providers.contains(provider);

  // ── connection ─────────────────────────────────────────────────────────

  Future<void> connect({bool probeUpdate = true}) async {
    _busy = true;
    _activity = 'connecting to pi bridge';
    _setBusy(true);
    try {
      _status = await _client.status();
      if (_status.reachable) {
        _lastError = null;
        try {
          await refreshModels();
        } catch (e) {
          _lastError = _short(e);
        }
        if (probeUpdate && autoUpdate) {
          unawaited(_autoUpdatePass());
        }
      } else {
        _lastError = _status.error ?? 'bridge unreachable';
      }
    } finally {
      _activity = '';
      _setBusy(false);
    }
    _restartAutoTimer();
  }

  void setBaseUrl(String url) {
    final next = url.trim();
    if (next.isEmpty || next == _baseUrl) return;
    _baseUrl = next.replaceAll(RegExp(r'/+$'), '');
    _client.dispose();
    _client = PiBridgeClient(baseUrl: _baseUrl);
    _sessionOpen = false;
    unawaited(connect());
  }

  Future<void> refreshModels({bool force = false}) async {
    _busy = true;
    _activity = force ? 'refreshing model catalog' : 'loading models';
    _setBusy(true);
    try {
      _models = await _client.models(refresh: force);
      lastCatalogRefresh = DateTime.now();
      // Keep the status pill honest without a second round trip.
      if (_models.isNotEmpty) {
        _status = PiStatus(
          reachable: _status.reachable,
          installed: _status.installed,
          node: _status.node,
          nodeOk: _status.nodeOk,
          agentDir: _status.agentDir,
          providers: _status.providers,
          modelCount: _models.length,
          sessions: _status.sessions,
          error: _status.error,
        );
      }
      _lastError = null;
    } catch (e) {
      _lastError = _short(e);
    } finally {
      _activity = '';
      _setBusy(false);
    }
  }

  // ── auto-update ────────────────────────────────────────────────────────

  /// Arm or disarm the periodic background check. Enabling it while connected
  /// takes effect immediately; disabling cancels the pending timer.
  void setAutoUpdate(bool on) {
    if (autoUpdate == on) return;
    autoUpdate = on;
    _restartAutoTimer();
    if (on && connected) unawaited(_autoUpdatePass());
    notifyListeners();
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    if (!autoUpdate || !connected) return;
    _autoTimer = Timer.periodic(autoUpdateInterval, (_) {
      unawaited(_autoUpdatePass());
    });
  }

  /// Version probe + catalog refresh. Deliberately does **not** reinstall the
  /// CLI on its own: silently replacing the binary underneath a running agent
  /// would be the wrong default. Auto-install is opt-in via [applyUpdate].
  Future<void> _autoUpdatePass() async {
    _update = await _client.checkVersion();
    if (_update?.updateAvailable == true) {
      _lastError = 'pi ${_update!.latest} is available '
          '(installed ${_update!.installed})';
      notifyListeners();
      return;
    }
    try {
      await refreshModels(force: true);
    } catch (e) {
      _lastError = _short(e);
      notifyListeners();
    }
  }

  Future<PiUpdateCheck> checkForUpdate() async {
    _busy = true;
    _activity = 'checking for updates';
    _setBusy(true);
    try {
      _update = await _client.checkVersion();
      return _update!;
    } finally {
      _activity = '';
      _setBusy(false);
    }
  }

  /// Runs `pi update --self`. Call only on explicit user action.
  Future<Map<String, dynamic>> applyUpdate({String target = 'self'}) async {
    _busy = true;
    _activity = 'running pi update --$target';
    _setBusy(true);
    try {
      final r = await _client.update(target);
      lastUpdateRun = DateTime.now();
      // A fresh binary means the old catalog and session are stale.
      _sessionOpen = false;
      await _client.status().then((s) => _status = s);
      await refreshModels(force: true);
      _update = await _client.checkVersion();
      return {
        'ok': r.ok,
        'target': r.target,
        'installed': r.installed,
        'output': r.output,
      };
    } catch (e) {
      _lastError = _short(e);
      return {'ok': false, 'error': _short(e)};
    } finally {
      _activity = '';
      _setBusy(false);
    }
  }

  // ── keys / endpoints ───────────────────────────────────────────────────

  /// Writes the vault's keys into Pi's own `auth.json`.
  Future<Map<String, dynamic>> pushKeys(Map<String, String> byProvider) async {
    try {
      final r = await _client.pushKeys(byProvider);
      _status = await _client.status();
      notifyListeners();
      return r;
    } catch (e) {
      _lastError = _short(e);
      notifyListeners();
      return {'ok': false, 'error': _short(e)};
    }
  }

  /// Registers a custom OpenAI-compatible endpoint in `models.json`.
  Future<Map<String, dynamic>> registerEndpoint({
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
    String name = '',
  }) async {
    try {
      final r = await _client.registerEndpoint(
        provider: provider,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        name: name,
      );
      await refreshModels(force: true);
      return r;
    } catch (e) {
      _lastError = _short(e);
      notifyListeners();
      return {'ok': false, 'error': _short(e)};
    }
  }

  // ── running a turn on real Pi ──────────────────────────────────────────

  /// A direct conversation turn, for the PI tab's chat surface.
  ///
  /// Unlike [runAgentTurn] this does not go through an [AgentRuntime]; it
  /// streams straight into the caller's transcript. That keeps the interactive
  /// terminal honest — what you type is exactly what Pi receives.
  Stream<PiEvent> converse(String message) async* {
    if (!connected) {
      throw StateError(
        'pi bridge is not connected — start it with: node /home/user/pi-bridge/server.mjs',
      );
    }
    await _ensureSession();
    _busy = true;
    _activity = 'pi is working';
    notifyListeners();
    try {
      yield* _client.prompt(_sessionId, message);
    } finally {
      _busy = false;
      _activity = '';
      notifyListeners();
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionOpen) return;
    await _client.openSession(name: _sessionId);
    _sessionOpen = true;
  }

  /// The [PiRunner] handed to [AgentLoop]: streams one Pi run into an agent's
  /// transcript and the terminal's event feed.
  Future<void> runAgentTurn(
    AgentRuntime agent,
    String task,
    void Function(AgentRuntime agent, AgentEvent event) onEvent,
  ) async {
    if (!connected) {
      throw StateError('pi bridge is not connected');
    }
    await _ensureSession();

    agent.setState(AgentRunState.thinking, 'pi: starting run');
    onEvent(agent, AgentEvent(
      kind: AgentEventKind.info,
      text: 'pi ${_status.versionLabel} · ${agent.piModel.isEmpty ? 'default model' : agent.piModel}',
    ));

    // Persist the model choice on the Pi side when the agent pins one.
    final cursor = await _client.startPrompt(_sessionId, _promptFor(agent, task));

    var at = cursor;
    var idlePolls = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    var settled = false;

    while (!settled && DateTime.now().isBefore(deadline)) {
      final batch = await _client.poll(_sessionId, at);
      at = batch.cursor;
      if (batch.events.isEmpty) {
        idlePolls++;
        if (idlePolls > 8) break;
      } else {
        idlePolls = 0;
      }
      for (final e in batch.events) {
        _applyEvent(agent, e, onEvent);
      }
      settled = batch.settled;
    }

    if (!settled) {
      onEvent(agent, const AgentEvent(
        kind: AgentEventKind.warn,
        text: 'pi run did not settle in time (poll deadline)',
      ));
    }
    if (agent.state == AgentRunState.thinking ||
        agent.state == AgentRunState.toolCall) {
      agent.setState(
        agent.transcript.isNotEmpty && agent.transcript.last.role == AgentRole.assistant
            ? AgentRunState.done
            : AgentRunState.error,
        settled ? 'pi: done' : 'pi: timed out',
      );
    }
    onEvent(agent, AgentEvent(
      kind: AgentEventKind.done,
      text: 'pi run settled',
    ));
  }

  /// Pi's system prompt already describes its tools; prepend only the
  /// persona the fleet assigned, so behaviour stays recognisably Pi's.
  String _promptFor(AgentRuntime agent, String task) {
    final persona = agent.persona.trim();
    if (persona.isEmpty) return task;
    return '${agent.name} operating inside Starlight Terminal. $persona\n\n'
        'TASK: $task';
  }

  void _applyEvent(
    AgentRuntime agent,
    PiEvent e,
    void Function(AgentRuntime, AgentEvent) onEvent,
  ) {
    switch (e.type) {
      case 'agent_start':
        agent.setState(AgentRunState.thinking, 'pi: run started');
      case 'agent_settled':
        agent.tokensIn += e.inputTokens;
        agent.tokensOut += e.outputTokens;
        if (!e.isError) agent.setState(AgentRunState.done, 'pi: settled');
      case 'turn_start':
        agent.setState(AgentRunState.thinking, 'pi: turn');
      case 'thinking_delta':
        onEvent(agent, AgentEvent(
          kind: AgentEventKind.thinking,
          text: _clip(e.text ?? '', 200),
        ));
      case 'text_delta':
        onEvent(agent, AgentEvent(
          kind: AgentEventKind.message,
          text: _clip(e.text ?? '', 200),
        ));
      case 'message':
        final text = (e.text ?? '').trim();
        if (text.isEmpty) return;
        agent.addMessage(AgentMessage(
          role: e.isError ? AgentRole.system : AgentRole.assistant,
          text: text,
          createdAt: DateTime.now(),
        ));
        onEvent(agent, AgentEvent(
          kind: e.isError ? AgentEventKind.warn : AgentEventKind.message,
          text: _clip(text, 300),
        ));
        if (e.isError) {
          agent.setState(AgentRunState.error, 'pi: provider error');
        }
      case 'tool_start':
        agent.setState(
          AgentRunState.toolCall,
          'pi: ${e.toolName}',
        );
        agent.noteTool('${e.toolName}(${e.toolArgs ?? ''})');
        onEvent(agent, AgentEvent(
          kind: AgentEventKind.tool,
          text: '${e.toolName} ${e.toolArgs ?? ''}'.trim(),
        ));
      case 'tool_end':
        final text = (e.text ?? '').trim();
        if (text.isNotEmpty) {
          agent.addMessage(AgentMessage(
            role: AgentRole.tool,
            text: text,
            toolName: e.toolName,
            createdAt: DateTime.now(),
          ));
        }
        onEvent(agent, AgentEvent(
          kind: e.isError ? AgentEventKind.warn : AgentEventKind.toolResult,
          text: text.isEmpty ? '${e.toolName} finished' : _clip(text, 300),
        ));
      case 'error':
        agent.setState(AgentRunState.error, 'pi: error');
        agent.addMessage(AgentMessage(
          role: AgentRole.system,
          text: e.text ?? '',
          createdAt: DateTime.now(),
        ));
        onEvent(agent, AgentEvent(
          kind: AgentEventKind.warn,
          text: _clip(e.text ?? '', 300),
        ));
    }
  }

  Future<void> abortAgent() async {
    if (!_sessionOpen) return;
    await _client.abort(_sessionId);
    notifyListeners();
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _client.dispose();
    super.dispose();
  }

  static String _clip(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  static String _short(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return s.length > 180 ? '${s.substring(0, 180)}…' : s;
  }
}
