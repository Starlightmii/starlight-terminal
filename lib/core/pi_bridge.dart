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

  String get shortContext {
    final w = contextWindow;
    if (w == null) return '—';
    if (w >= 1000000) return '${(w / 1000000).toStringAsFixed(w % 1000000 == 0 ? 0 : 1)}M';
    if (w >= 1000) return '${(w / 1000).round()}k';
    return '$w';
  }

  static PiModel fromJson(Map<String, dynamic> j) => PiModel(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? j['id'] ?? '').toString(),
        provider: (j['provider'] ?? '').toString(),
        api: (j['api'] ?? '').toString(),
        reasoning: j['reasoning'] == true,
        input: (j['input'] as List?)?.map((e) => e.toString()).toList() ??
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
  bool get hasAuth => providers.isNotEmpty;

  static const PiStatus offline = PiStatus(error: 'pi bridge not running');

  static PiStatus fromJson(Map<String, dynamic> j) => PiStatus(
        installed: j['installed']?.toString(),
        node: j['node']?.toString(),
        nodeOk: j['nodeOk'] == true,
        providers: (j['providers'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        modelCount: (j['modelCount'] as num?)?.toInt() ?? 0,
        agentDir: (j['agentDir'] ?? '').toString(),
        sessions: (j['sessions'] as num?)?.toInt() ?? 0,
        reachable: j['ok'] == true,
      );
}

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
    this.text,
    this.isError = false,
  });

  final String type;
  final Map<String, dynamic> raw;
  final String? toolName;
  final String? text;
  final bool isError;

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

  static String _flatten(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

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
    final isError = (m?['stopReason'] == 'error') ||
        (j['isError'] == true) ||
        (j['error'] != null && type == 'bridge_error');
    return PiEvent(
      type: type,
      raw: j,
      toolName: j['toolName']?.toString(),
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
  PiBridgeClient({String? baseUrl})
      : baseUrl = baseUrl ?? defaultBaseUrl;

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

  static const Duration _connectTimeout = Duration(seconds: 6);

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  void dispose() => _http.close();

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final res = await _http.get(_u(path, query), headers: {
      'accept': 'application/json',
    }).timeout(timeout ?? _connectTimeout);
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
    final res = await _http.post(
      _u(path),
      headers: {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(timeout ?? const Duration(seconds: 60));
    if (res.statusCode >= 400) {
      throw PiBridgeException('HTTP ${res.statusCode}', res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw PiBridgeException('bad response shape', res.body);
    }
    return decoded;
  }

  /// True when the bridge process is up and `pi` is on PATH.
  Future<PiStatus> status() async {
    try {
      final j = await _getJson('/status');
      return PiStatus.fromJson(j);
    } catch (e) {
      return PiStatus(error: _msg(e));
    }
  }

  Future<PiVersionInfo> version() async {
    try {
      final j = await _getJson('/version', timeout: const Duration(seconds: 20));
      return PiVersionInfo.fromJson(j);
    } catch (e) {
      return PiVersionInfo(error: _msg(e));
    }
  }

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
      if (name != null) 'name': name,
    });
  }

  /// Start a long-lived pi session. Returns the session id.
  Future<String> openSession({String? name, Map<String, dynamic>? onState}) async {
    final j = await _postJson(
      '/sessions${name == null ? '' : '?name=${Uri.encodeQueryComponent(name)}'}',
      const {},
      timeout: const Duration(seconds: 40),
    );
    final id = (j['sessionId'] ?? '').toString();
    if (id.isEmpty) throw PiBridgeException('no session id', jsonEncode(j));
    return id;
  }

  /// Send an arbitrary allow-listed pi RPC command (set_model, compact, …).
  Future<Map<String, dynamic>> command(
    String sessionId,
    Map<String, dynamic> payload,
  ) =>
      _postJson('/sessions/$sessionId/command', payload,
          timeout: const Duration(seconds: 60));

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

  /// Submit a prompt and stream pi's events until the run settles.
  ///
  /// The POST itself returns as soon as pi accepts the prompt; events are then
  /// long-polled from the replay buffer, which means no event can be missed
  /// even if the first records land before the POST resolves.
  Stream<PiEvent> prompt(String sessionId, String message) async* {
    final accepted = await _postJson(
      '/sessions/$sessionId/prompt',
      {'message': message},
      timeout: const Duration(seconds: 90),
    );
    if (accepted['ok'] == false) {
      throw PiBridgeException(
        (accepted['error'] ?? 'prompt rejected').toString(),
        jsonEncode(accepted),
      );
    }

    var cursor = (accepted['cursor'] as num?)?.toInt() ?? 0;

    // Poll until pi reports the session settled. A generous cap keeps a wedged
    // provider from pinning the UI forever; pi's own abort is the fast path.
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> page;
      try {
        page = await _getJson(
          '/sessions/$sessionId/events',
          query: {'since': '$cursor', 'wait': '20000'},
          timeout: const Duration(seconds: 40),
        );
      } on PiBridgeException {
        rethrow;
      } catch (e) {
        throw PiBridgeException('event stream lost', _msg(e));
      }

      final events = (page['events'] as List?) ?? const [];
      cursor = (page['cursor'] as num?)?.toInt() ?? cursor;
      for (final e in events.whereType<Map>()) {
        yield PiEvent.fromJson(Map<String, dynamic>.from(e));
      }
      if (page['settled'] == true && events.isEmpty) return;
      if (page['alive'] == false) return;
    }
  }

  /// Abort the in-flight run, keeping the session usable.
  Future<void> abort(String sessionId) async {
    try {
      await _postJson('/sessions/$sessionId/abort', const {},
          timeout: const Duration(seconds: 20));
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

  /// Run `pi update`, `pi update --all` or `pi update --models`.
  Future<PiUpdateResult> update(String target) async {
    try {
      final j = await _postJson(
        '/update',
        {'target': target},
        timeout: const Duration(minutes: 6),
      );
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

  static String _msg(Object e) =>
      e is PiBridgeException ? '${e.message}${e.detail.isEmpty ? '' : ' — ${e.detail}'}' : e.toString();
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
