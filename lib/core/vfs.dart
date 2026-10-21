import 'package:flutter/foundation.dart';

/// A tiny in-memory filesystem so the terminal has somewhere to work.
///
/// There is no real `/system` to write to on Android, and a shell without files
/// is a toy. This gives `ls`, `cd`, `cat`, `mkdir`, `rm`, `echo >` real
/// behaviour backed by a flat path->content map.
class Vfs extends ChangeNotifier {
  Vfs() {
    _files['/home/user/README'] =
        'Starlight Terminal — an on-device agent shell.\n'
        'Type `help` for commands. `pi` drives the agent.\n';
    _files['/home/user/notes/pi.txt'] =
        'pi runs as a coding agent. In this build the agent core is native,\n'
        'driven by whichever provider key you set in KEYS.\n';
    _dirs.addAll([
      '/',
      '/home',
      '/home/user',
      '/home/user/notes',
      '/home/user/projects',
      '/tmp',
    ]);
  }

  final Map<String, String> _files = {};
  final Set<String> _dirs = {'/'};
  String cwd = '/home/user';

  String get prompt => cwd.replaceFirst('/home/user', '~');

  String _abs(String p) {
    if (p.isEmpty) return cwd;
    if (p.startsWith('/')) return _norm(p);
    if (p == '~') return '/home/user';
    if (p.startsWith('~/')) return _norm('/home/user/${p.substring(2)}');
    return _norm('$cwd/$p');
  }

  String _norm(String p) {
    final out = <String>[];
    for (final seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(seg);
      }
    }
    return '/${out.join('/')}';
  }

  bool isDir(String p) => _dirs.contains(_abs(p));
  bool exists(String p) => isDir(p) || _files.containsKey(_abs(p));

  /// Sorted directory entries, or null when the path is not a directory.
  List<MapEntry<String, bool>>? list(String p) {
    final path = _abs(p);
    if (!_dirs.contains(path)) return null;
    final prefix = path == '/' ? '/' : '$path/';
    final out = <String, bool>{};
    for (final d in _dirs) {
      if (d == path || !d.startsWith(prefix)) continue;
      final rest = d.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      out[rest] = true;
    }
    for (final f in _files.keys) {
      if (!f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      out[rest] = false;
    }
    final keys = out.keys.toList()..sort();
    return keys.map((k) => MapEntry(k, out[k]!)).toList();
  }

  String? read(String p) => _files[_abs(p)];

  /// Writes a file, creating parent directories as needed.
  void write(String p, String content) {
    final path = _abs(p);
    var parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.isEmpty) parent = '/';
    var acc = '';
    for (final seg in parent.split('/').where((s) => s.isNotEmpty)) {
      acc = '$acc/$seg';
      _dirs.add(acc);
    }
    _files[path] = content;
    notifyListeners();
  }

  bool mkdir(String p) {
    final path = _abs(p);
    if (exists(path)) return false;
    var acc = '';
    for (final seg in path.split('/').where((s) => s.isNotEmpty)) {
      acc = '$acc/$seg';
      _dirs.add(acc);
    }
    notifyListeners();
    return true;
  }

  bool remove(String p) {
    final path = _abs(p);
    if (_files.remove(path) != null) {
      notifyListeners();
      return true;
    }
    final prefix = '$path/';
    final n = _files.length;
    _files.removeWhere((k, _) => k.startsWith(prefix));
    _dirs.removeWhere((d) => d == path || d.startsWith(prefix));
    if (_files.length != n || _dirs.contains(path)) {
      notifyListeners();
      return true;
    }
    notifyListeners();
    return _files.length != n;
  }

  bool cd(String p) {
    final path = _abs(p);
    if (!_dirs.contains(path)) return false;
    cwd = path;
    notifyListeners();
    return true;
  }

  int get fileCount => _files.length;
}
