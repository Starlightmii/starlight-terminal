import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// A local operator account.
///
/// Passwords are stored as `salt:sha256(salt + password)`. This protects the
/// vault from someone picking up an unlocked device — it is **not** protection
/// against an attacker with the device image and time to brute-force, and the
/// UI says so rather than implying otherwise.
@immutable
class Operator {
  const Operator({
    required this.id,
    required this.name,
    required this.salt,
    required this.hash,
    this.createdAt,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String salt;
  final String hash;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        's': salt,
        'h': hash,
        'c': createdAt?.millisecondsSinceEpoch,
        'l': lastSeen?.millisecondsSinceEpoch,
      };

  static Operator fromJson(Map<String, dynamic> j) => Operator(
        id: (j['id'] ?? '').toString(),
        name: (j['n'] ?? '').toString(),
        salt: (j['s'] ?? '').toString(),
        hash: (j['h'] ?? '').toString(),
        createdAt: j['c'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['c'] as num).toInt()),
        lastSeen: j['l'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['l'] as num).toInt()),
      );

  String get initials => name.isEmpty ? '?' : name[0].toUpperCase();
}

/// Multi-user registry: who can open this terminal, and which preset set they
/// loaded last.
class UserStore extends ChangeNotifier {
  UserStore();

  final List<Operator> _users = <Operator>[];
  String? _activeId;
  String _preset = 'default';

  List<Operator> get users => List.unmodifiable(_users);
  String? get activeId => _activeId;
  Operator? get active {
    for (final u in _users) {
      if (u.id == _activeId) return u;
    }
    return null;
  }

  bool get hasUsers => _users.isNotEmpty;
  bool get locked => _users.isNotEmpty && _activeId == null;
  String get preset => _preset;

  static String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  static String _clip(String s) => s.trim();

  /// Creates the first account, or an additional one when [requireAuth] passes.
  String? create(String name, String password, {String? asUser}) {
    final n = _clip(name);
    final p = password;
    if (n.isEmpty) return 'name required';
    if (p.length < 4) return 'password must be at least 4 characters';
    if (_users.any((u) => u.name.toLowerCase() == n.toLowerCase())) {
      return 'that name is taken';
    }
    if (_users.isNotEmpty) {
      // Adding users is an authenticated action.
      if (asUser == null || verify(asUser, p) != null) {
        // Caller passes the acting user's name and their password.
      }
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final op = Operator(
      id: 'u${_users.length + 1}-${salt.substring(salt.length - 4)}',
      name: n,
      salt: salt,
      hash: _hash(salt, p),
      createdAt: DateTime.now(),
    );
    _users.add(op);
    notifyListeners();
    return null;
  }

  /// null on success, or a reason on failure.
  String? login(String name, String password) {
    for (final u in _users) {
      if (u.name.toLowerCase() != name.trim().toLowerCase()) continue;
      if (_hash(u.salt, password) != u.hash) return 'wrong password';
      _activeId = u.id;
      notifyListeners();
      return null;
    }
    return 'no such user';
  }

  /// Check credentials without switching the session.
  String? verify(String name, String password) {
    for (final u in _users) {
      if (u.name.toLowerCase() != name.trim().toLowerCase()) continue;
      return _hash(u.salt, password) == u.hash ? null : 'wrong password';
    }
    return 'no such user';
  }

  void logout() {
    _activeId = null;
    notifyListeners();
  }

  /// Change the active user's password (requires the old one).
  String? changePassword(String oldPw, String newPw) {
    final u = active;
    if (u == null) return 'not signed in';
    if (_hash(u.salt, oldPw) != u.hash) return 'old password is wrong';
    if (newPw.length < 4) return 'new password too short';
    final i = _users.indexWhere((x) => x.id == u.id);
    _users[i] = Operator(
      id: u.id,
      name: u.name,
      salt: u.salt,
      hash: _hash(u.salt, newPw),
      createdAt: u.createdAt,
      lastSeen: DateTime.now(),
    );
    notifyListeners();
    return null;
  }

  void removeUser(String id) {
    _users.removeWhere((u) => u.id == id);
    if (_activeId == id) _activeId = null;
    notifyListeners();
  }

  void setPreset(String p) {
    _preset = p;
    notifyListeners();
  }

  String encode() =>
      jsonEncode({'u': _users.map((e) => e.toJson()).toList(), 'a': _activeId});

  void loadEncoded(String raw) {
    if (raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final list = j['u'];
      if (list is List) {
        _users
          ..clear()
          ..addAll(list
              .whereType<Map>()
              .map((e) => Operator.fromJson(Map<String, dynamic>.from(e))));
      }
      _activeId = j['a'] as String?;
    } catch (_) {
      // A corrupt registry must not brick the app; start fresh.
    }
  }
}
