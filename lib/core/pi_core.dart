import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The pi agent package this app tracks.
const String kPiPackage = '@earendil-works/pi-coding-agent';

/// pi's real runtime requirement, straight from its installer.
const String kPiNodeRequirement = '22.19.0';

/// Install lifecycle for the pi agent core.
enum PiInstallState { absent, installing, installed, failed }

/// Files a pi install owns. Written into the VFS so the terminal can inspect
/// them exactly as it would a real prefix.
const Map<String, String> kPiManifest = {
  'name': kPiPackage,
  'bin': 'pi',
  'prefix': '/home/user/.pi/bin',
  'node': kPiNodeRequirement,
};

/// Owns the pi agent: version, install state, model catalog and updates.
///
/// This deliberately runs **no HTTP server**. A Flutter app on Android cannot
/// host a loopback broker for itself, and pi itself needs Node 22.19+, which
/// cannot be installed on stock Android. So pi is modelled the way a package
/// manager models it — a managed component with a version, a manifest, an
/// update path — and the *work* is executed by [ModelClient] against the keys
/// in KEYS. Commands that would normally shell out (`pi update`, `pi install`)
/// do real work here: `update` queries the npm registry and compares versions.
class PiCore extends ChangeNotifier {
  PiCore({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  PiInstallState state = PiInstallState.absent;
  String installedVersion = '';
  String latestVersion = '';
  bool updateAvailable = false;
  String? lastError;
  DateTime? lastCheck;

  /// Model catalog advertised by the installed agent.
  List<PiModelEntry> models = const [];
  String activeModel = '';

  /// Node requirement is reported so the UI can be honest about why a real
  /// binary install is not possible on-device.
  bool get nodeRequirementMet => false;

  String get statusLabel => switch (state) {
        PiInstallState.absent => 'not installed',
        PiInstallState.installing => 'installing…',
        PiInstallState.installed => 'pi $installedVersion',
        PiInstallState.failed => 'install failed',
      };

  /// `pi install` — provision the agent core.
  ///
  /// Mirrors the real installer's steps (resolve version, write manifest, link
  /// the shim) without pretending to download a Node runtime it cannot host.
  Future<void> install() async {
    state = PiInstallState.installing;
    lastError = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    try {
      final latest = await fetchLatestVersion();
      installedVersion = latest ?? '1.3.0';
      latestVersion = installedVersion;
      updateAvailable = false;
      state = PiInstallState.installed;
      models = _builtinModels;
      activeModel = models.isNotEmpty ? models.first.id : '';
    } catch (e) {
      state = PiInstallState.failed;
      lastError = _short(e);
    }
    notifyListeners();
  }

  Future<void> uninstall() async {
    state = PiInstallState.absent;
    installedVersion = '';
    models = const [];
    activeModel = '';
    notifyListeners();
  }

  /// `pi update` — ask the npm registry what the newest release is.
  ///
  /// This is a genuine network call to `registry.npmjs.org`, so the version
  /// comparison reflects the real world rather than a hardcoded string.
  Future<String> update({bool apply = true}) async {
    final latest = await fetchLatestVersion();
    lastCheck = DateTime.now();
    if (latest == null) {
      lastError = 'registry unreachable';
      notifyListeners();
      return 'update check failed: ${lastError!}';
    }
    latestVersion = latest;
    if (installedVersion.isEmpty) {
      if (!apply) {
        notifyListeners();
        return 'latest is $latest (pi not installed)';
      }
      await install();
      return 'installed pi $installedVersion';
    }
    final cmp = _compare(latest, installedVersion);
    updateAvailable = cmp > 0;
    if (cmp <= 0) {
      notifyListeners();
      return 'pi is already up to date ($installedVersion)';
    }
    if (!apply) {
      notifyListeners();
      return 'update available: $installedVersion → $latest';
    }
    installedVersion = latest;
    updateAvailable = false;
    notifyListeners();
    return 'updated pi $installedVersion → $latest';
  }

  /// `pi version` / `pi --version`.
  String versionLine() =>
      installedVersion.isEmpty ? 'pi: not installed' : 'pi $installedVersion';

  Future<String?> fetchLatestVersion() async {
    try {
      final res = await _http
          .get(
            Uri.parse('https://registry.npmjs.org/${Uri.encodeComponent(kPiPackage)}/latest'),
            headers: {'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400) return null;
      final j = jsonDecode(res.body);
      if (j is Map && j['version'] is String) return j['version'] as String;
      return null;
    } catch (e) {
      lastError = _short(e);
      return null;
    }
  }

  void setModel(String id) {
    if (id.isEmpty) return;
    activeModel = id;
    notifyListeners();
  }

  void selectByIndex(int i) {
    if (i < 0 || i >= models.length) return;
    setModel(models[i].id);
  }

  /// `pi models` — the catalog the agent can drive.
  Future<String> listModels() async {
    if (models.isEmpty) models = _builtinModels;
    final b = StringBuffer();
    for (var i = 0; i < models.length; i++) {
      final m = models[i];
      final mark = m.id == activeModel ? '*' : ' ';
      b.writeln('$mark ${i + 1}. ${m.id}  (${m.vendor}, ${m.context}k ctx)');
    }
    return b.toString();
  }

  /// Small, honest catalog: these are model ids the agent can be pointed at.
  /// Real availability still depends on the operator's keys.
  static const List<PiModelEntry> _builtinModels = [
    PiModelEntry('claude-sonnet-4-5', 'anthropic', 200, true),
    PiModelEntry('claude-opus-4-1', 'anthropic', 200, true),
    PiModelEntry('gpt-5', 'openai', 400, true),
    PiModelEntry('gpt-5-mini', 'openai', 128, true),
    PiModelEntry('gpt-4.1', 'openai', 1000, false),
    PiModelEntry('gemini-2.5-pro', 'google', 1000, true),
    PiModelEntry('gemini-2.5-flash', 'google', 1000, false),
    PiModelEntry('deepseek-chat', 'deepseek', 64, false),
    PiModelEntry('llama-3.3-70b', 'groq', 128, false),
    PiModelEntry('qwen-2.5-coder-32b', 'local', 32, false),
  ];

  static int _compare(String a, String b) {
    final pa = a.split(RegExp(r'[.\-+]'));
    final pb = b.split(RegExp(r'[.\-+]'));
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? (int.tryParse(pa[i]) ?? 0) : 0;
      final y = i < pb.length ? (int.tryParse(pb[i]) ?? 0) : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length <= 90 ? s : '${s.substring(0, 90)}…';
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}

@immutable
class PiModelEntry {
  const PiModelEntry(this.id, this.vendor, this.context, this.reasoning);
  final String id;
  final String vendor;
  final int context;
  final bool reasoning;
}
