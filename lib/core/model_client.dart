import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'providers.dart';

/// One streamed chunk from a model.
enum ChunkKind { text, thinking, tool, done, error }

@immutable
class ModelChunk {
  const ModelChunk(this.kind, this.text);
  final ChunkKind kind;
  final String text;
}

/// Talks to language models **directly from the app**.
///
/// This is the piece that replaces the old loopback bridge. A phone cannot
/// reach a server running on the desktop, so every call now goes straight to
/// the provider the operator configured in KEYS — an ordinary outbound HTTPS
/// request, no sidecar process involved.
///
/// Supports both wire formats that matter:
///  * `openai`      — `POST {base}/chat/completions`, SSE `data:` frames
///  * `anthropic`   — `POST {base}/messages`, typed SSE events
class ModelClient {
  ModelClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Streams a completion. Yields [ChunkKind.text] deltas as they arrive.
  Stream<ModelChunk> stream({
    required Provider provider,
    required List<Map<String, String>> messages,
    String? model,
    int maxTokens = 2048,
    String? system,
    bool web = kIsWeb,
  }) async* {
    final key = provider.apiKey.trim();
    if (key.isEmpty) {
      yield const ModelChunk(
        ChunkKind.error,
        'no API key for this provider — add one in KEYS',
      );
      return;
    }
    if (web && provider.baseUrl.contains('api.anthropic.com')) {
      // Anthropic does not send CORS headers for browser callers; say so rather
      // than surfacing an opaque XHR failure.
      yield const ModelChunk(
        ChunkKind.error,
        'Anthropic blocks browser requests (no CORS). Use the Android build, '
            'or switch to an OpenAI-compatible provider for web preview.',
      );
      return;
    }

    final anthropic = provider.baseUrl.contains('anthropic');
    final uri = anthropic
        ? Uri.parse('${_trim(provider.baseUrl)}/messages')
        : provider.chatEndpoint;

    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': anthropic ? 'text/event-stream' : 'application/json',
      if (anthropic) 'x-api-key': key else 'authorization': 'Bearer $key',
      if (anthropic) 'anthropic-version': '2023-06-01',
    };

    final body = anthropic
        ? jsonEncode({
            'model': model ?? 'claude-sonnet-4-5',
            'max_tokens': maxTokens,
            'stream': true,
            if (system != null && system.isNotEmpty) 'system': system,
            'messages': messages
                .map((m) => {'role': m['role'], 'content': m['content']})
                .toList(),
          })
        : jsonEncode({
            'model': model ?? 'gpt-4o-mini',
            'max_tokens': maxTokens,
            'stream': true,
            'messages': [
              if (system != null && system.isNotEmpty)
                {'role': 'system', 'content': system},
              ...messages
                  .map((m) => {'role': m['role'], 'content': m['content']}),
            ],
          });

    http.StreamedResponse res;
    try {
      final req = http.Request('POST', uri)..headers.addAll(headers);
      req.body = body;
      res = await _http.send(req).timeout(const Duration(seconds: 60));
    } catch (e) {
      yield ModelChunk(ChunkKind.error, _explain(e));
      return;
    }

    if (res.statusCode >= 400) {
      final text = await res.stream.bytesToString();
      yield ModelChunk(
        ChunkKind.error,
        _httpError(res.statusCode, text),
      );
      return;
    }

    final ctype = res.headers['content-type'] ?? '';
    // Some gateways ignore `stream` and answer with a single JSON document.
    if (!ctype.contains('event-stream')) {
      final text = await res.stream.bytesToString();
      final parsed = _parseWhole(text, anthropic);
      if (parsed != null) {
        yield ModelChunk(ChunkKind.text, parsed);
      } else {
        yield ModelChunk(ChunkKind.error, 'unexpected response: ${_clip(text)}');
      }
      yield const ModelChunk(ChunkKind.done, '');
      return;
    }

    final buf = StringBuffer();
    await for (final line
        in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        final j = jsonDecode(payload);
        if (j is! Map) continue;
        if (anthropic) {
          final type = j['type'];
          if (type == 'content_block_delta') {
            final d = j['delta'];
            if (d is Map) {
              if (d['type'] == 'text_delta' && d['text'] is String) {
                buf.write(d['text']);
                yield ModelChunk(ChunkKind.text, d['text'] as String);
              } else if (d['type'] == 'thinking_delta' && d['thinking'] is String) {
                yield ModelChunk(ChunkKind.thinking, d['thinking'] as String);
              }
            }
          } else if (type == 'error') {
            yield ModelChunk(ChunkKind.error, '${j['error'] ?? 'stream error'}');
            return;
          }
        } else {
          final choices = j['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices.first as Map)['delta'];
            if (delta is Map && delta['content'] is String) {
              final s = delta['content'] as String;
              buf.write(s);
              yield ModelChunk(ChunkKind.text, s);
            }
          }
          if (j['error'] != null) {
            yield ModelChunk(ChunkKind.error, '${j['error']}');
            return;
          }
        }
      } catch (_) {
        // Ignore keep-alives and malformed frames; the stream stays usable.
      }
    }
    yield const ModelChunk(ChunkKind.done, '');
  }

  /// Convenience for one-shot calls (agent steps, summaries).
  Future<String> complete({
    required Provider provider,
    required String prompt,
    String? model,
    String? system,
    int maxTokens = 2048,
  }) async {
    final b = StringBuffer();
    String? err;
    await for (final c in stream(
      provider: provider,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      model: model,
      system: system,
      maxTokens: maxTokens,
    )) {
      if (c.kind == ChunkKind.text) b.write(c.text);
      if (c.kind == ChunkKind.error) err = c.text;
    }
    if (err != null && b.isEmpty) throw StateError(err);
    return b.toString();
  }

  static String _trim(String s) => s.endsWith('/')
      ? s.substring(0, s.length - 1)
      : s;

  static String? _parseWhole(String raw, bool anthropic) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      if (anthropic) {
        final content = j['content'];
        if (content is List && content.isNotEmpty) {
          final first = content.first;
          if (first is Map && first['text'] is String) {
            return first['text'] as String;
          }
        }
        return null;
      }
      final choices = j['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = (choices.first as Map)['message'];
        if (msg is Map && msg['content'] is String) return msg['content'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _httpError(int code, String body) {
    if (code == 401 || code == 403) {
      return 'auth rejected ($code) — the key for this provider looks wrong.';
    }
    if (code == 404) {
      return 'model or endpoint not found (404). Check the model id and base URL.';
    }
    if (code == 429) return 'rate limited (429) — retry shortly.';
    return 'HTTP $code: ${_clip(body)}';
  }

  static String _explain(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'network unreachable — check the device connection.';
    }
    if (s.contains('TimeoutException')) return 'request timed out.';
    return s.length <= 160 ? s : '${s.substring(0, 160)}…';
  }

  static String _clip(String s) =>
      s.length <= 160 ? s : '${s.substring(0, 160)}…';

  void dispose() => _http.close();
}
