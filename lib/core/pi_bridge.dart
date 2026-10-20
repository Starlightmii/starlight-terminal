import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One model as reported by pi's own catalog.
@immutable
class PiModel {
  const PiModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.api,
    this.reasoning = false,
    this.input = const ['text'],
    this.contextWindow,
    this.maxTokens,
  });

  final String id;
  final String name;
  final String provider;
  final String api;
  final bool reasoning;
  final List<String> input;
  final int? contextWindow;
  final int? maxTokens;

  bool get acceptsImages => input.contains('image');

  /// `provider/id`, the form pi itself accepts for `--model`.
  String get qualifiedId => '$provider/$id';

  /// Alias kept for the PI panel's model rows.
  bool get supportsImages => acceptsImages;

  String get shortContext {
    final w = contextWindow;
    if (w == null) return '—';
    if (w >= 1000000) {
      return '${(w / 1000000).toStringAsFixed(w % 1000000 == 0 ? 0 : 1)}M';
    }
    if (w >= 1000) return '${(w / 1000).round()}k';
    return '$w';
  }

  static PiModel fromJson(Map<String, dynamic> j) => PiModel(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? j['id'] ?? '').toString(),
    provider: (j['provider'] ?? '').toString(),
    api: (j['api'] ?? '').toString(),
    reasoning: j['reasoning'] == true,
    input:
        (j['input'] as List?)?.map((e) => e.toString()).toList() ??
        const ['text'],
    contextWindow: (j['contextWindow'] as num?)?.toInt(),
    maxTokens: (j['maxTokens'] as num?)?.toInt(),
  );
}

/// Pi's install/version state, as probed from the bridge.
@immutable
class PiStatus {
  const PiStatus({
    this.installed,
    this.node,
    this.nodeOk = false,
    this.providers = const [],
    this.modelCount = 0,
    this.agentDir = '',
    this.sessions = 0,
    this.reachable = false,
    this.error,
  });

  final String? installed;
  final String? node;
  final bool nodeOk;
  final List<String> providers;
  final int modelCount;
  final String agentDir;
  final int sessions;
  final bool reachable;
  final String? error;

  bool get isInstalled => installed != null && installed!.isNotEmpty;

  /// Short label for status pills, e.g. `pi 1.3.0`.
  String get versionLabel => isInstalled ? 'pi $installed' : 'pi not found';
  bool get hasAuth => providers.isNotEmpty;

  static const PiStatus offline = PiStatus(error: 'pi bridge not running');

  static PiStatus fromJson(Map<String, dynamic> j) => PiStatus(
    installed: j['installed']?.toString(),
    node: j['node']?.toString(),
    nodeOk: j['nodeOk'] == true,
    providers:
        (j['providers'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    modelCount: (j['modelCount'] as num?)?.toInt() ?? 0,
    agentDir: (j['agentDir'] ?? '').toString(),
    sessions: (j['sessions'] as num?)?.toInt() ?? 0,
    reachable: j['ok'] == true,
  );
}

/// Alias kept for the PI panel: a version comparison result.
typedef PiUpdateCheck = PiVersionInfo;

/// Result of comparing the installed CLI with the npm registry.
@immutable
class PiVersionInfo {
  const PiVersionInfo({
    this.installed,
    this.latest,
    this.updateAvailable = false,
    this.relation = 'unknown',
    this.error,
  });

  final String? installed;
  final String? latest;
  final bool updateAvailable;

  /// `behind`, `current`, `ahead`, or `unknown`.
  final String relation;
  final String? error;

  /// One-line description for the PI panel.
  String get summary {
    if (error != null && error!.isNotEmpty) return 'version probe failed: $error';
    if (installed == null) return 'pi not installed';
    if (latest == null) return 'pi $installed (upstream unknown)';
    if (updateAvailable) return 'pi $installed → $latest available';
    if (relation == 'ahead') return 'pi $installed (ahead of npm $latest)';
    return 'pi $installed is current';
  }

  static PiVersionInfo fromJson(Map<String, dynamic> j) => PiVersionInfo(
    installed: j['installed']?.toString(),
    latest: j['latest']?.toString(),
    updateAvailable: j['updateAvailable'] == true,
    relation: (j['relation'] ?? 'unknown').toString(),
    error: j['error']?.toString(),
  );
}

/// One event emitted by pi during a run.
///
/// Pi's wire schema is intentionally preserved: `type` is pi's own event name
/// (agent_start, tool_execution_start, message_update, …), so anything reading
/// this stream can be checked against pi's documentation directly.
@immutable
class PiEvent {
  const PiEvent({
    required this.type,
    required this.raw,
    this.toolName,
    this.toolArgs,
    this.text,
    this.isError = false,
  });

  final String type;
  final Map<String, dynamic> raw;
  final String? toolName;
  final String? toolArgs;
  final String? text;
  final bool isError;

  // ── Narrowed accessors ────────────────────────────────────────────────
  // Pi's wire records are heterogeneous; these pull the handful of fields the
  // terminal cares about so callers never index the raw map by hand.

  /// Assistant text carried by this event, when it carries any.
  String? get messageText {
    final body = raw['message'];
    if (body is Map) {
      final t = _messagePreview(body);
      return t.isEmpty ? null : t;
    }
    final d = raw['assistantMessageEvent'];
    if (d is Map) {
      final delta = d['delta'];
      if (delta != null && delta.toString().isNotEmpty) return delta.toString();
    }
    return null;
  }

  /// Streaming text delta from `message_update`.
  String? get textDelta {
    final d = raw['assistantMessageEvent'];
    if (d is Map && d['type'] == 'text_delta') {
      final v = d['delta'];
      return v?.toString();
    }
    return null;
  }

  /// Streaming reasoning delta from `message_update`.
  String? get thinkingDelta {
    final d = raw['assistantMessageEvent'];
    if (d is Map && d['type'] == 'thinking_delta') {
      final v = d['delta'];
      return v?.toString();
    }
    return null;
  }

  int get inputTokens {
    final usage = _usage;
    return (usage?['input'] as num?)?.toInt() ?? 0;
  }

  int get outputTokens {
    final usage = _usage;
    return (usage?['output'] as num?)?.toInt() ?? 0;
  }

  Map? get _usage {
    final direct = raw['usage'];
    if (direct is Map) return direct;
    final m = raw['message'];
    if (m is Map) {
      final u = m['usage'];
      if (u is Map) return u;
    }
    return null;
  }

  /// Normalised event kind.
  ///
  /// pi emits streaming detail nested inside `message_update` and tool activity
  /// under `tool_execution_*`. Consumers that only need "something streamed" or
  /// "a tool started" read this instead of digging into [raw]. The raw record
  /// is always available, so nothing is lost.
  String get kind {
    switch (type) {
      case 'message_update':
        final ev = raw['assistantMessageEvent'];
        if (ev is Map) {
          switch (ev['type']) {
            case 'text_delta':
              return 'text_delta';
            case 'thinking_delta':
            case 'thinking_start':
              return 'thinking_delta';
            case 'toolcall_start':
              return 'tool_start';
            case 'toolcall_end':
              return 'tool_end';
            case 'error':
              return 'error';
          }
        }
        return 'update';
      case 'tool_execution_start':
        return 'tool_start';
      case 'tool_execution_end':
        return 'tool_end';
      case 'tool_execution_update':
        return 'tool_update';
      case 'message_end':
        return isError ? 'error' : 'message';
      case 'bridge_error':
        return 'error';
      default:
        return type;
    }
  }

  /// Streaming text carried by this event, if any.
  String get deltaText {
    final ev = raw['assistantMessageEvent'];
    if (ev is Map) return (ev['delta'] ?? '').toString();
    return '';
  }

  /// A single human-readable line for the terminal transcript.
  String get summary {
    switch (type) {
      case 'agent_start':
        return 'agent run started';
      case 'agent_end':
        final n = raw['messageCount'];
        return 'agent run ended${n is num ? ' ($n messages)' : ''}';
      case 'agent_settled':
        return raw['aborted'] == true ? 'run aborted' : 'run settled';
      case 'turn_start':
        return 'turn started';
      case 'turn_end':
        return 'turn ended';
      case 'message_start':
      case 'message_end':
        final m = raw['message'] as Map?;
        final role = (m?['role'] ?? '?').toString();
        if (type == 'message_start') return 'message ($role)';
        final preview = _messagePreview(m);
        return preview.isEmpty ? 'message ($role)' : preview;
      case 'message_update':
        final d = raw['assistantMessageEvent'] as Map?;
        final delta = (d?['delta'] ?? '').toString();
        return delta.isEmpty ? 'streaming' : delta;
      case 'tool_execution_start':
        final args = raw['args'];
        return '$toolName ${_compactArgs(args)}'.trim();
      case 'tool_execution_update':
        return '$toolName working';
      case 'tool_execution_end':
        return '$toolName ${isError ? 'failed' : 'done'}'
            '${_durationSuffix()}';
      case 'bridge_error':
        return text ?? 'bridge error';
      default:
        return text ?? type;
    }
  }

  String _durationSuffix() {
    final ms = raw['durationMs'];
    if (ms is! num) return '';
    return ' (${ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s'})';
  }

  static String _messagePreview(Map? m) {
    final content = m?['content'];
    if (content is String) return _flatten(content);
    if (content is List) {
      final parts = <String>[];
      for (final b in content) {
        if (b is! Map) continue;
        if (b['type'] == 'text') parts.add((b['text'] ?? '').toString());
      }
      return _flatten(parts.join(' '));
    }
    return '';
  }

  static String _flatten(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _compactArgs(Object? args) {
    if (args == null) return '';
    if (args is Map) {
      return args.entries
          .take(2)
          .map((e) {
            final v = e.value.toString();
            return '${e.key}=${v.length > 28 ? '${v.substring(0, 28)}…' : v}';
          })
          .join(' ');
    }
    final s = args.toString();
    return s.length > 40 ? '${s.substring(0, 40)}…' : s;
  }

  static PiEvent fromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? '').toString();
    final m = j['message'] as Map?;
    final isError =
        (m?['stopReason'] == 'error') ||
        (j['isError'] == true) ||
        (j['error'] != null && type == 'bridge_error');
    return PiEvent(
      type: type,
      raw: j,
      toolName: j['toolName']?.toString(),
      toolArgs: PiEvent._compactArgs(j['args']),
      text: j['error']?.toString(),
      isError: isError,
    );
  }
}

/// Client for the local Pi bridge. The bridge owns real `pi --mode rpc`
/// subprocesses and re-publishes their JSONL records over HTTP.
///
/// Transport note: this deliberately uses **long-poll** rather than
/// EventSource. `EventSource` cannot issue a POST, and pi requires a POST to
/// start a prompt; it is also unavailable on Android. Long-polling the same
/// replay buffer works identically on web and mobile.
class PiBridgeClient {
  PiBridgeClient({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  /// On web, resolve against the page origin so a co-hosted proxy works.
  /// On Android, allow an explicit override or a LAN host.
  static String get defaultBaseUrl {
    if (kIsWeb) {
      final base = Uri.base;
      if (base.host.isNotEmpty) return '${base.origin}/pi';
    }
    return const String.fromEnvironment(
      'PI_BRIDGE_URL',
      defaultValue: 'http://127.0.0.1:5077',
    );
  }

  final String baseUrl;
  final http.Client _http = http.Client();

  static const Duration _connectTimeout = Duration(seconds: 8);

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  void dispose() => _http.close();

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final res = await _http
        .get(_u(path, query), headers: {'accept': 'application/json'})
        .timeout(timeout ?? _connectTimeout);
    if (res.statusCode >= 400) {
      throw PiBridgeException('HTTP ${res.statusCode}', res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw PiBridgeException('bad response shape', res.body);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final res = await _http
        .post(
          _u(path),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout ?? const Duration(seconds: 60));
    if (res.statusCode >= 400) {
      throw PiBridgeException('HTTP ${res.statusCode}', res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw PiBridgeException('bad response shape', res.body);
    }
    return decoded;
  }

  // ── probing ────────────────────────────────────────────────────────────

  /// True when the bridge process is up and `pi` is on PATH.
  Future<PiStatus> status() async {
    try {
      return PiStatus.fromJson(await _getJson('/status'));
    } catch (e) {
      return PiStatus(error: _msg(e));
    }
  }

  Future<PiVersionInfo> version() async {
    try {
      return PiVersionInfo.fromJson(
        await _getJson('/version', timeout: const Duration(seconds: 25)),
      );
    } catch (e) {
      return PiVersionInfo(error: _msg(e));
    }
  }

  /// Alias used by the connector: version probe with a typed result.
  Future<PiVersionInfo> checkVersion() => version();

  /// Models from pi's live catalog (cached server-side for 60s).
  Future<List<PiModel>> models({bool refresh = false}) async {
    final j = await _getJson(
      '/models',
      query: refresh ? {'refresh': '1'} : null,
      timeout: const Duration(seconds: 100),
    );
    final list = (j['models'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => PiModel.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ── keys / endpoints ───────────────────────────────────────────────────

  /// Write API keys into pi's own `~/.pi/agent/auth.json`.
  ///
  /// [entries] maps a pi provider id (e.g. `openai`) to a raw key. An empty
  /// value removes the provider.
  Future<List<String>> syncAuth(Map<String, String> entries) async {
    final j = await _postJson('/auth', {'entries': entries});
    return ((j['providers'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  /// Alias used by the connector: write keys into pi's `auth.json`.
  Future<Map<String, dynamic>> pushKeys(Map<String, String> byProvider) async {
    try {
      final providers = await syncAuth(byProvider);
      return {'ok': true, 'providers': providers};
    } catch (e) {
      return {'ok': false, 'error': _msg(e)};
    }
  }

  /// Register a custom OpenAI-compatible endpoint in `models.json`.
  Future<void> registerProvider({
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
    String api = 'openai-completions',
    String? name,
  }) async {
    await _postJson('/models/provider', {
      'provider': provider,
      'baseUrl': baseUrl,
      'model': model,
      'api': api,
      if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
      if (name != null && name.isNotEmpty) 'name': name,
    });
  }

  /// Alias used by the connector: register a custom endpoint in `models.json`.
  Future<Map<String, dynamic>> registerEndpoint({
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
    String name = '',
  }) async {
    try {
      await registerProvider(
        provider: provider,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        name: name,
      );
      return {'ok': true, 'provider': provider};
    } catch (e) {
      return {'ok': false, 'error': _msg(e)};
    }
  }

  // ── sessions ───────────────────────────────────────────────────────────

  /// Start a long-lived pi session. Returns the session id.
  Future<String> openSession({String? name}) async {
    final j = await _postJson(
      '/sessions'
      '${name == null ? '' : '?name=${Uri.encodeQueryComponent(name)}'}',
      const {},
      timeout: const Duration(seconds: 45),
    );
    final id = (j['sessionId'] ?? '').toString();
    if (id.isEmpty) throw PiBridgeException('no session id', jsonEncode(j));
    return id;
  }

  /// Send an allow-listed pi RPC command (`set_model`, `compact`, …).
  Future<Map<String, dynamic>> command(
    String sessionId,
    Map<String, dynamic> payload,
  ) => _postJson(
    '/sessions/$sessionId/command',
    payload,
    timeout: const Duration(seconds: 60),
  );

  /// Select the model pi should use for this session.
  Future<bool> setModel(
    String sessionId, {
    required String provider,
    required String modelId,
  }) async {
    final j = await command(sessionId, {
      'type': 'set_model',
      'provider': provider,
      'modelId': modelId,
    });
    return j['ok'] == true;
  }

  /// Submit a prompt and return the cursor *before* any of its records.
  ///
  /// Read it back with [poll] so the caller controls pacing and can interleave
  /// its own state updates with each batch.
  Future<int> startPrompt(String sessionId, String message) async {
    final accepted = await _postJson('/sessions/$sessionId/prompt', {
      'message': message,
    }, timeout: const Duration(seconds: 90));
    if (accepted['ok'] == false) {
      throw PiBridgeException(
        (accepted['error'] ?? 'prompt rejected').toString(),
        jsonEncode(accepted),
      );
    }
    return (accepted['cursor'] as num?)?.toInt() ?? 0;
  }

  /// Long-poll the replay buffer from [since].
  ///
  /// Long-polling (not EventSource) because `EventSource` cannot POST — pi
  /// requires a POST to start a prompt — and it does not exist on Android.
  Future<PiPollBatch> poll(
    String sessionId,
    int since, {
    Duration wait = const Duration(seconds: 20),
  }) async {
    final page = await _getJson(
      '/sessions/$sessionId/events',
      query: {'since': '$since', 'wait': '${wait.inMilliseconds}'},
      timeout: wait + const Duration(seconds: 25),
    );
    final events = ((page['events'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PiEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return PiPollBatch(
      cursor: (page['cursor'] as num?)?.toInt() ?? since,
      settled: page['settled'] == true,
      alive: page['alive'] != false,
      events: events,
    );
  }

  /// Submit a prompt and stream every event until the run settles.
  Stream<PiEvent> prompt(String sessionId, String message) async* {
    var at = await startPrompt(sessionId, message);
    final deadline = DateTime.now().add(const Duration(minutes: 6));
    while (DateTime.now().isBefore(deadline)) {
      final batch = await poll(sessionId, at);
      at = batch.cursor;
      for (final e in batch.events) {
        yield e;
      }
      if (!batch.alive) return;
      if (batch.settled && batch.events.isEmpty) return;
    }
  }

  /// Abort the in-flight run, keeping the session usable.
  Future<void> abort(String sessionId) async {
    try {
      await _postJson(
        '/sessions/$sessionId/abort',
        const {},
        timeout: const Duration(seconds: 20),
      );
    } catch (_) {
      // Aborting an idle session is not an error worth surfacing.
    }
  }

  Future<void> closeSession(String sessionId) async {
    try {
      await _http
          .delete(_u('/sessions/$sessionId'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      /* best effort */
    }
  }

  // ── update ─────────────────────────────────────────────────────────────

  /// Run `pi update`, `pi update --all` or `pi update --models`.
  Future<PiUpdateResult> update(String target) async {
    try {
      final j = await _postJson('/update', {
        'target': target,
      }, timeout: const Duration(minutes: 6));
      return PiUpdateResult(
        ok: j['ok'] == true,
        target: target,
        installed: j['installed']?.toString(),
        output: '${j['stdout'] ?? ''}${j['stderr'] ?? ''}'.trim(),
      );
    } catch (e) {
      return PiUpdateResult(
        ok: false,
        target: target,
        installed: null,
        output: _msg(e),
      );
    }
  }

  static String _msg(Object e) => e is PiBridgeException
      ? '${e.message}${e.detail.isEmpty ? '' : ' — ${e.detail}'}'
      : e.toString();
}

@immutable
class PiUpdateResult {
  const PiUpdateResult({
    required this.ok,
    required this.target,
    this.installed,
    this.output = '',
  });

  final bool ok;
  final String target;
  final String? installed;
  final String output;
}

class PiBridgeException implements Exception {
  PiBridgeException(this.message, this.detail);
  final String message;
  final String detail;

  /// Turn a raw transport failure into something a terminal user can act on.
  static String hint(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('clientexception')) {
      return 'pi bridge unreachable — start it with: node /home/user/pi-bridge/server.mjs';
    }
    if (s.contains('401')) return 'pi rejected the request (check auth)';
    return 'pi bridge error';
  }

  @override
  String toString() => 'PiBridgeException($message)';
}

/// One page of buffered pi events, returned by [PiBridgeClient.poll].
@immutable
class PiEventPage {
  const PiEventPage({
    required this.events,
    required this.cursor,
    required this.settled,
    required this.alive,
  });

  final List<PiEvent> events;
  final int cursor;
  final bool settled;
  final bool alive;
}

/// One page of pi events read back from the replay buffer.
@immutable
class PiPollBatch {
  const PiPollBatch({
    required this.cursor,
    required this.settled,
    required this.alive,
    this.events = const [],
  });

  /// Pass this back as `since` on the next poll.
  final int cursor;

  /// Pi has no further automatic work for the run.
  final bool settled;

  /// The underlying `pi` child process is still running.
  final bool alive;

  final List<PiEvent> events;

  bool get isEmpty => events.isEmpty;
}
