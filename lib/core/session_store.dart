import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'memory.dart';

/// Who is on the other end of a session.
enum SessionKind {
  /// A conversation with the Pi coding agent.
  pi,

  /// A conversation with one of the fleet agents.
  bot,

  /// A scheduled / autonomous agent run.
  job,
}

/// One message inside a session transcript.
@immutable
class SessionMessage {
  const SessionMessage({
    required this.role,
    required this.text,
    required this.at,
    this.toolName,
    this.isError = false,
  });

  /// 'you' | 'pi' | 'agent' | 'tool' | 'sys'
  final String role;
  final String text;
  final DateTime at;
  final String? toolName;
  final bool isError;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'r': role,
        't': text,
        'a': at.millisecondsSinceEpoch,
        if (toolName != null) 'n': toolName,
        if (isError) 'e': true,
      };

  static SessionMessage? fromJson(Map<String, dynamic> j) {
    final text = j['t'] as String?;
    if (text == null) return null;
    return SessionMessage(
      role: j['r'] as String? ?? 'sys',
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch((j['a'] as num?)?.toInt() ?? 0),
      toolName: j['n'] as String?,
      isError: j['e'] == true,
    );
  }

  String get glyph => switch (role) {
        'you' => '❯',
        'pi' => 'π',
        'agent' => '◈',
        'tool' => '⚒',
        _ => '·',
      };
}

/// A durable conversation. Sessions are the unit the SESSIONS tab lists and the
/// MAP screen anchors, and they own the memories extracted from them.
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    this.agentId,
    this.piModel = '',
    this.tags = const <String>[],
    this.pinned = false,
  });

  final String id;

  /// Mutable: auto-derived from the first user line, then left alone.
  String title;

  final SessionKind kind;
  final DateTime createdAt;
  final String? agentId;

  /// For pi sessions: which provider/model was last selected.
  String piModel;

  List<String> tags;
  bool pinned;

  DateTime lastActivity = DateTime.now();
  int tokensIn = 0;
  int tokensOut = 0;
  int toolCalls = 0;
  int errorCount = 0;

  /// Cumulative cost estimate in US cents, if the provider reported it.
  double costCents = 0;

  final List<SessionMessage> messages = <SessionMessage>[];

  int get messageCount => messages.length;

  bool get isPi => kind == SessionKind.pi;

  String get kindLabel => switch (kind) {
        SessionKind.pi => 'PI',
        SessionKind.bot => 'BOT',
        SessionKind.job => 'JOB',
      };

  String get preview {
    if (messages.isEmpty) return 'empty session';
    for (var i = messages.length - 1; i >= 0; i--) {
      final t = messages[i].text.trim();
      if (t.isNotEmpty) {
        final line = t.split('\n').first;
        return line.length > 90 ? '${line.substring(0, 90)}…' : line;
      }
    }
    return 'empty session';
  }

  String get ageLabel {
    final d = DateTime.now().difference(lastActivity);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  void append(SessionMessage m) {
    messages.add(m);
    lastActivity = DateTime.now();
    if (m.isError) errorCount += 1;
    if (m.role == 'tool') toolCalls += 1;
    notifyListeners();
  }

  void addUsage({int tin = 0, int tout = 0}) {
    tokensIn += tin;
    tokensOut += tout;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'i': id,
        'ti': title,
        'k': kind.name,
        'c': createdAt.millisecondsSinceEpoch,
        'la': lastActivity.millisecondsSinceEpoch,
        if (agentId != null) 'ag': agentId,
        if (piModel.isNotEmpty) 'pm': piModel,
        if (tags.isNotEmpty) 'g': tags,
        if (pinned) 'p': true,
        'tin': tokensIn,
        'tout': tokensOut,
        'tc': toolCalls,
        'ec': errorCount,
        'm': messages.map((m) => m.toJson()).toList(),
      };

  static ChatSession? fromJson(Map<String, dynamic> j) {
    final id = j['i'] as String?;
    if (id == null) return null;
    final s = ChatSession(
      id: id,
      title: j['ti'] as String? ?? 'untitled',
      kind: SessionKind.values.firstWhere(
        (v) => v.name == j['k'],
        orElse: () => SessionKind.pi,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (j['c'] as num?)?.toInt() ?? 0,
      ),
      agentId: j['ag'] as String?,
      piModel: j['pm'] as String? ?? '',
      tags: (j['g'] as List?)?.map((e) => '$e').toList() ?? const <String>[],
      pinned: j['p'] == true,
    );
    s.lastActivity = DateTime.fromMillisecondsSinceEpoch(
      (j['la'] as num?)?.toInt() ?? s.createdAt.millisecondsSinceEpoch,
    );
    s.tokensIn = (j['tin'] as num?)?.toInt() ?? 0;
    s.tokensOut = (j['tout'] as num?)?.toInt() ?? 0;
    s.toolCalls = (j['tc'] as num?)?.toInt() ?? 0;
    s.errorCount = (j['ec'] as num?)?.toInt() ?? 0;
    for (final raw in (j['m'] as List?) ?? const []) {
      if (raw is Map<String, dynamic>) {
        final m = SessionMessage.fromJson(raw);
        if (m != null) s.messages.add(m);
      }
    }
    return s;
  }
}

/// Owns every session in the app and the memory store they feed.
///
/// Bounded on purpose: a terminal that runs for weeks must not grow without
/// limit. Old, unpinned, message-less sessions are evicted first.
class SessionStore extends ChangeNotifier {
  SessionStore({required this.memories, this.maxSessions = 80});

  final MemoryStore memories;
  final int maxSessions;

  final List<ChatSession> _sessions = <ChatSession>[];
  String? _activeId;
  int _seq = 0;

  /// Newest-first.
  List<ChatSession> get all => List<ChatSession>.unmodifiable(_sessions);

  List<ChatSession> byKind(SessionKind k) =>
      _sessions.where((s) => s.kind == k).toList();

  ChatSession? get active {
    final id = _activeId;
    if (id == null) return null;
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  String? get activeId => _activeId;

  ChatSession? byId(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  ChatSession create({
    required SessionKind kind,
    String title = 'untitled',
    String? agentId,
    String piModel = '',
    List<String> tags = const <String>[],
  }) {
    final s = ChatSession(
      id: 'ses-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      title: title,
      kind: kind,
      createdAt: DateTime.now(),
      agentId: agentId,
      piModel: piModel,
      tags: tags,
    );
    _sessions.insert(0, s);
    _activeId = s.id;
    _enforceCapacity();
    notifyListeners();
    return s;
  }

  void setActive(String? id) {
    if (_activeId == id) return;
    _activeId = id;
    notifyListeners();
  }

  /// The live pi session, created on demand. One per app run keeps the bridge
  /// child count sane and gives the PI tab a stable conversation.
  ChatSession ensurePi({String model = ''}) {
    for (final s in _sessions) {
      if (s.kind == SessionKind.pi && s.id == _activeId) return s;
    }
    for (final s in _sessions) {
      if (s.kind == SessionKind.pi) {
        _activeId = s.id;
        return s;
      }
    }
    return create(kind: SessionKind.pi, title: 'pi session', piModel: model);
  }

  bool remove(String id) {
    for (var i = 0; i < _sessions.length; i++) {
      if (_sessions[i].id == id) {
        _sessions.removeAt(i);
        if (_activeId == id) {
          _activeId = _sessions.isEmpty ? null : _sessions.first.id;
        }
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// Appends a message *and* mirrors it into the memory store when it carries
  /// durable value. That mirroring is what fills the MAP screen.
  void appendMessage(
    String sessionId,
    SessionMessage m, {
    bool remember = false,
    String? starId,
  }) {
    final s = byId(sessionId);
    if (s == null) return;
    s.append(m);

    // Auto-title from the first real user turn.
    if (m.role == 'you' && s.title == 'untitled') {
      final line = m.text.trim().split('\n').first;
      s.title = line.length > 48 ? '${line.substring(0, 48)}…' : line;
    }

    if (remember && m.text.trim().isNotEmpty && !m.isError) {
      memories.add(
        text: m.text,
        source: s.isPi
            ? MemorySource.pi
            : (s.kind == SessionKind.job ? MemorySource.agent : MemorySource.bot),
        kind: m.role == 'you' ? MemoryKind.task : MemoryKind.result,
        sessionId: s.id,
        author: m.role == 'you' ? 'operator' : (s.isPi ? 'pi' : s.agentId),
        tags: s.tags,
        starId: starId,
        weight: s.pinned ? 0.95 : 0.6,
      );
    }
    notifyListeners();
  }

  void _enforceCapacity() {
    if (_sessions.length <= maxSessions) return;
    final victims = _sessions.where((s) => !s.pinned).toList()
      ..sort((a, b) => a.lastActivity.compareTo(b.lastActivity));
    final drop = _sessions.length - maxSessions;
    for (var i = 0; i < drop && i < victims.length; i++) {
      _sessions.remove(victims[i]);
    }
  }

  void clearAll() {
    _sessions.clear();
    _activeId = null;
    notifyListeners();
  }

  /// Aggregate numbers for the SESSIONS header and SYSTEM panel.
  Map<String, int> get stats {
    var msgs = 0;
    var tools = 0;
    var errors = 0;
    var tin = 0;
    var tout = 0;
    for (final s in _sessions) {
      msgs += s.messageCount;
      tools += s.toolCalls;
      errors += s.errorCount;
      tin += s.tokensIn;
      tout += s.tokensOut;
    }
    return {
      'sessions': _sessions.length,
      'messages': msgs,
      'tools': tools,
      'errors': errors,
      'tokensIn': tin,
      'tokensOut': tout,
      'memories': memories.length,
    };
  }

  // ── persistence ────────────────────────────────────────────────────────

  /// NDJSON, one session per line. Transcript bodies are capped so a long
  /// session cannot blow the shared_preferences size budget.
  String encode({int maxMessagesPerSession = 120}) {
    final b = StringBuffer();
    for (final s in _sessions.reversed) {
      final j = s.toJson();
      final msgs = (j['m'] as List?) ?? const [];
      if (msgs.length > maxMessagesPerSession) {
        j['m'] = msgs.sublist(msgs.length - maxMessagesPerSession);
      }
      b.writeln(jsonEncode(j));
    }
    return b.toString();
  }

  void loadEncoded(String? raw) {
    _sessions.clear();
    _activeId = null;
    if (raw == null || raw.isEmpty) {
      notifyListeners();
      return;
    }
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line);
        if (j is! Map<String, dynamic>) continue;
        final s = ChatSession.fromJson(j);
        if (s != null) _sessions.insert(0, s);
      } catch (_) {
        // skip
      }
    }
    _sessions.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    _activeId = _sessions.isEmpty ? null : _sessions.first.id;
    for (final s in _sessions) {
      s.addListener(notifyListeners);
    }
    notifyListeners();
  }
}
