import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Where a memory came from. Every chat surface in the app writes memories,
/// so the map can show one coherent picture of what the operator has learned.
enum MemorySource { console, bot, pi, agent, system }

/// What kind of thing was remembered.
enum MemoryKind { observation, fact, task, result, note }

/// One durable memory.
///
/// Deliberately flat and string-heavy: it has to survive a JSON round-trip
/// through shared_preferences on web and still encode cheaply.
@immutable
class Memory {
  const Memory({
    required this.id,
    required this.text,
    required this.createdAt,
    this.source = MemorySource.console,
    this.kind = MemoryKind.note,
    this.sessionId,
    this.author,
    this.tags = const <String>[],
    this.starId,
    this.weight = 1.0,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final MemorySource source;
  final MemoryKind kind;

  /// Which chat session produced it, if any.
  final String? sessionId;

  /// Human label for the producer: agent name, 'pi', 'you'.
  final String? author;

  final List<String> tags;

  /// Optional sky anchor — lets a memory be plotted on the map.
  final String? starId;

  /// 0..1 salience. Pinned memories stay when the store has to evict.
  final double weight;

  Memory copyWith({
    String? text,
    MemoryKind? kind,
    List<String>? tags,
    double? weight,
    String? starId,
  }) {
    return Memory(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      source: source,
      kind: kind ?? this.kind,
      sessionId: sessionId,
      author: author,
      tags: tags ?? this.tags,
      starId: starId ?? this.starId,
      weight: weight ?? this.weight,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'i': id,
        't': text,
        'c': createdAt.millisecondsSinceEpoch,
        's': source.name,
        'k': kind.name,
        if (sessionId != null) 'sid': sessionId,
        if (author != null) 'a': author,
        if (tags.isNotEmpty) 'g': tags,
        if (starId != null) 'st': starId,
        'w': weight,
      };

  static Memory? fromJson(Map<String, dynamic> j) {
    final id = j['i'] as String?;
    final text = j['t'] as String?;
    if (id == null || text == null) return null;
    return Memory(
      id: id,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (j['c'] as num?)?.toInt() ?? 0,
      ),
      source: MemorySource.values.firstWhere(
        (v) => v.name == j['s'],
        orElse: () => MemorySource.console,
      ),
      kind: MemoryKind.values.firstWhere(
        (v) => v.name == j['k'],
        orElse: () => MemoryKind.note,
      ),
      sessionId: j['sid'] as String?,
      author: j['a'] as String?,
      tags: (j['g'] as List?)?.map((e) => '$e').toList() ?? const <String>[],
      starId: j['st'] as String?,
      weight: (j['w'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Cheap content fingerprint used for de-duplication.
  String get fingerprint =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String get ageLabel {
    final d = DateTime.now().difference(createdAt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// Compact, indexed, bounded memory store.
///
/// Design notes:
/// * Newest-first list, so rendering never sorts.
/// * A `fingerprint -> id` map makes de-duplication O(1) on write.
/// * Tag, session and source indexes are integer lists over the same backing
///   array, so filtering a 500-entry store stays cheap.
/// * Eviction is weight-aware: pinned (weight >= 0.9) memories are dropped last.
class MemoryStore extends ChangeNotifier {
  MemoryStore({this.capacity = 600});

  /// Hard ceiling. Beyond this the lowest-weight oldest entries go.
  final int capacity;

  final List<Memory> _items = <Memory>[];
  final Map<String, String> _byFingerprint = <String, String>{};
  final Map<String, List<String>> _bySession = <String, List<String>>{};
  final Map<String, List<String>> _byTag = <String, List<String>>{};
  final Map<String, int> _bySource = <String, int>{};

  int _seq = 0;

  /// All memories, newest first.
  List<Memory> get all => List<Memory>.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  List<Memory> forSession(String sessionId) => (_bySession[sessionId] ??
          const <String>[])
      .map((id) => _resolve(id))
      .whereType<Memory>()
      .toList();

  List<Memory> forSource(MemorySource source) =>
      _items.where((m) => m.source == source).toList();

  List<Memory> withTag(String tag) => (_byTag[tag.toLowerCase()] ??
          const <String>[])
      .map((id) => _resolve(id))
      .whereType<Memory>()
      .toList();

  /// Memories that can be plotted on the map.
  List<Memory> get anchored =>
      _items.where((m) => m.starId != null && m.starId!.isNotEmpty).toList();

  int countOf(MemorySource source) => _bySource[source.name] ?? 0;

  Memory? _resolve(String id) {
    for (final m in _items) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Returns the stored memory, or the pre-existing duplicate if the text was
  /// already known. Never throws.
  Memory add({
    required String text,
    MemorySource source = MemorySource.console,
    MemoryKind kind = MemoryKind.note,
    String? sessionId,
    String? author,
    List<String> tags = const <String>[],
    String? starId,
    double weight = 1.0,
  }) {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw ArgumentError('refusing to store an empty memory');
    }
    final probe = Memory(
      id: '',
      text: clean,
      createdAt: DateTime.now(),
      source: source,
      kind: kind,
      sessionId: sessionId,
      author: author,
      tags: tags,
      starId: starId,
      weight: weight,
    );
    final existing = _byFingerprint[probe.fingerprint];
    if (existing != null) {
      final hit = _resolve(existing);
      if (hit != null) return hit;
    }

    final m = Memory(
      id: 'mem-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      text: clean,
      createdAt: DateTime.now(),
      source: source,
      kind: kind,
      sessionId: sessionId,
      author: author,
      tags: tags.map((t) => t.toLowerCase()).toList(),
      starId: starId,
      weight: weight,
    );
    _index(m);
    _enforceCapacity();
    notifyListeners();
    return m;
  }

  void _index(Memory m) {
    _items.insert(0, m);
    _byFingerprint[m.fingerprint] = m.id;
    if (m.sessionId != null) {
      (_bySession[m.sessionId!] ??= <String>[]).add(m.id);
    }
    for (final t in m.tags) {
      (_byTag[t] ??= <String>[]).add(m.id);
    }
    _bySource[m.source.name] = (_bySource[m.source.name] ?? 0) + 1;
  }

  void _unindex(Memory m) {
    _items.remove(m);
    _byFingerprint.remove(m.fingerprint);
    if (m.sessionId != null) _bySession[m.sessionId!]?.remove(m.id);
    for (final t in m.tags) {
      _byTag[t]?.remove(m.id);
    }
    final n = (_bySource[m.source.name] ?? 1) - 1;
    if (n <= 0) {
      _bySource.remove(m.source.name);
    } else {
      _bySource[m.source.name] = n;
    }
  }

  /// Drops the least valuable entries until we are back under [capacity].
  /// "Least valuable" = lowest weight, then oldest.
  void _enforceCapacity() {
    if (_items.length <= capacity) return;
    final victims = _items.toList()
      ..sort((a, b) {
        final w = a.weight.compareTo(b.weight);
        if (w != 0) return w;
        return a.createdAt.compareTo(b.createdAt);
      });
    final drop = _items.length - capacity;
    for (var i = 0; i < drop && i < victims.length; i++) {
      _unindex(victims[i]);
    }
  }

  bool remove(String id) {
    for (final m in _items.toList()) {
      if (m.id == id) {
        _unindex(m);
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  bool pin(String id) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id == id) {
        _items[i] = _items[i].copyWith(weight: 1.0);
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void clear() {
    _items.clear();
    _byFingerprint.clear();
    _bySession.clear();
    _byTag.clear();
    _bySource.clear();
    notifyListeners();
  }

  /// Free-text search across body, tags and author.
  List<Memory> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return _items
        .where(
          (m) =>
              m.text.toLowerCase().contains(q) ||
              (m.author?.toLowerCase().contains(q) ?? false) ||
              m.tags.any((t) => t.contains(q)),
        )
        .toList();
  }

  // ── persistence ────────────────────────────────────────────────────────

  /// Newline-delimited JSON. One record per line keeps the blob small and
  /// means a single corrupt record cannot destroy the whole store.
  String encode() => _items.reversed.map((m) => jsonEncode(m.toJson())).join('\n');

  void loadEncoded(String? raw) {
    _items.clear();
    _byFingerprint.clear();
    _bySession.clear();
    _byTag.clear();
    _bySource.clear();
    if (raw == null || raw.isEmpty) {
      notifyListeners();
      return;
    }
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line);
        if (j is! Map<String, dynamic>) continue;
        final m = Memory.fromJson(j);
        if (m != null) _index(m);
      } catch (_) {
        // Skip the bad line, keep the rest.
      }
    }
    _enforceCapacity();
    notifyListeners();
  }

  /// Aggregate stats for the SYSTEM panel.
  Map<String, int> get sourceBreakdown => Map<String, int>.from(_bySource);
}
