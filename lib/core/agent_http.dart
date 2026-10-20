import 'package:http/http.dart' as http;

import 'agent_runtime.dart';

/// Installs the real HTTP implementation of [httpPostJson].
///
/// On web this is an XHR through `package:http`'s browser client, so vendor
/// CORS rules apply — which is why the KEYS panel flags providers that do not
/// send permissive `Access-Control-Allow-Origin` headers. On Android/iOS the
/// same call is a plain socket request with no CORS concept at all.
void installHttpBridge() {
  httpPostJsonImpl = ({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = http.Client();
    try {
      final resp = await client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode >= 400) {
        final snippet = resp.body.length > 300
            ? '${resp.body.substring(0, 300)}…'
            : resp.body;
        throw HttpError(resp.statusCode, snippet);
      }
      return resp.body;
    } finally {
      client.close();
    }
  };
}

class HttpError implements Exception {
  const HttpError(this.status, this.body);
  final int status;
  final String body;

  /// Human hint for the two failures people actually hit.
  String get hint {
    if (status == 401 || status == 403) {
      return 'key rejected (HTTP $status) — check it in the KEYS panel';
    }
    if (status == 429) return 'rate limited (HTTP 429) — slow down';
    return 'HTTP $status';
  }

  @override
  String toString() => hint;
}
