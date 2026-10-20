import 'package:flutter/foundation.dart';

/// Severity of a log line. Ordered so the UI can filter with `>=`.
enum LogLevel { debug, info, tool, warn, error }

/// One line in the app-wide log.
@immutable
class LogEntry {
  const LogEntry({
    required this.at,
    required this.level,
    required this.scope,
    required this.text,
  });

  final DateTime at;
  final LogLevel level;

  /// Which subsystem emitted it: 'pi', 'bridge', 'agent', 'keys', 'fx', …
  final String scope;
  final String text;

  String get timeLabel {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get levelLabel => switch (level) {
        LogLevel.debug => 'DBG',
        LogLevel.info => 'INF',
        LogLevel.tool => 'TUL',
        LogLevel.warn => 'WRN',
        LogLevel.error => 'ERR',
      };
}

/// A bounded, in-memory log sink for the whole application.
///
/// Everything that used to disappear into the console funnels here instead, so
/// the LOG tab can show one honest timeline of what the app did. Capped at
/// [capacity] — this is a tail, not an audit trail.
class AppLog extends ChangeNotifier {
  AppLog({this.capacity = 500});

  final int capacity;

  final List<LogEntry> _entries = <LogEntry>[];
  LogLevel _floor = LogLevel.debug;
  String _scopeFilter = '';

  /// Newest first.
  List<LogEntry> get all => List<LogEntry>.unmodifiable(_entries);

  LogLevel get floor => _floor;
  String get scopeFilter => _scopeFilter;

  int get length => _entries.length;

  int countOf(LogLevel l) => _entries.where((e) => e.level == l).length;

  /// Scopes seen so far, for the filter chips.
  List<String> get scopes {
    final s = <String>{};
    for (final e in _entries) {
      s.add(e.scope);
    }
    final out = s.toList()..sort();
    return out;
  }

  /// Entries passing the current filters, newest first.
  List<LogEntry> get visible {
    final q = _scopeFilter.trim().toLowerCase();
    return _entries.where((e) {
      if (e.level.index < _floor.index) return false;
      if (q.isEmpty) return true;
      return e.scope.toLowerCase() == q ||
          e.text.toLowerCase().contains(q);
    }).toList();
  }

  void setFloor(LogLevel l) {
    if (_floor == l) return;
    _floor = l;
    notifyListeners();
  }

  void setScopeFilter(String s) {
    if (_scopeFilter == s) return;
    _scopeFilter = s;
    notifyListeners();
  }

  void write(String text, {LogLevel level = LogLevel.info, String scope = 'app'}) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _entries.insert(
      0,
      LogEntry(at: DateTime.now(), level: level, scope: scope, text: clean),
    );
    if (_entries.length > capacity) _entries.removeLast();
    // Debug chatter must not repaint the whole app on every frame.
    if (level.index >= LogLevel.info.index) notifyListeners();
  }

  void debug(String s, {String scope = 'app'}) =>
      write(s, level: LogLevel.debug, scope: scope);

  void info(String s, {String scope = 'app'}) =>
      write(s, level: LogLevel.info, scope: scope);

  void tool(String s, {String scope = 'tool'}) =>
      write(s, level: LogLevel.tool, scope: scope);

  void warn(String s, {String scope = 'app'}) =>
      write(s, level: LogLevel.warn, scope: scope);

  void error(String s, {String scope = 'app'}) =>
      write(s, level: LogLevel.error, scope: scope);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Plain-text dump for the SYSTEM panel's copy/export action.
  String export() => _entries.reversed
      .map((e) => '${e.at.toIso8601String()} ${e.levelLabel} [${e.scope}] ${e.text}')
      .join('\n');
}
