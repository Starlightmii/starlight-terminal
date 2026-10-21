import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'providers.dart';

/// The pi agent package this app tracks.
const String kPiPackage = '@earendil-works/pi-coding-agent';

/// pi's real runtime requirement, straight from its installer.
const String kPiNodeRequirement = '22.19.0';

/// Install lifecycle for the pi agent core.
enum PiInstallState { absent, installing, installed, failed }

/// Files a pi install owns.
const Map<String, String> kPiManifest = {
  'name': kPiPackage,
  'bin': 'pi',
  'prefix': '/home/user/.pi/bin',
  'node': kPiNodeRequirement,
};

/// One addressable model.
///
/// A model is only useful if you know **which key pays for it**, so every entry
/// carries the vault provider it routes through. `id` is the wire id sent in the
/// request body; `providerId` picks the endpoint and credential.
@immutable
class PiModelEntry {
  const PiModelEntry(
    this.id,
    this.vendor,
    this.context,
    this.reasoning, {
    this.providerId = '',
    this.free = false,
    this.live = false,
  });

  final String id;
  final String vendor;
  final int context;
  final bool reasoning;

  /// Vault provider id (`openrouter`, `groq`, `custom-1`, …).
  final String providerId;

  /// Costs nothing to call (local inference or a `:free` tier).
  final bool free;

  /// True when the id was confirmed by the provider's own `/models` endpoint
  /// rather than assumed from the preset list.
  final bool live;

  /// `vendor/id` form used by `/model` and `pi models`.
  String get label => providerId.isEmpty ? id : '$providerId/$id';

  String get contextLabel => context <= 0 ? '—' : '$context k';

  Map<String, dynamic> toJson() => {
        'id': id,
        'vendor': vendor,
        'ctx': context,
        'reasoning': reasoning,
        'providerId': providerId,
        'free': free,
      };

  static PiModelEntry? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return PiModelEntry(
      id,
      (j['vendor'] ?? 'model').toString(),
      (j['ctx'] as num?)?.toInt() ?? 0,
      j['reasoning'] as bool? ?? false,
      providerId: (j['providerId'] ?? '').toString(),
      free: j['free'] as bool? ?? false,
    );
  }
}

/// Owns the pi agent: version, install state, model catalog and updates.
///
/// No HTTP server: a Flutter app on Android cannot host a loopback broker for
/// itself, and pi needs Node 22.19+, which stock Android cannot provide. pi is
/// modelled the way a package manager models it — a managed component with a
/// version, a manifest and a real npm update path — and the *work* is executed
/// by the app against the operator's keys.
///
/// The model catalog is deliberately **not** a hardcoded list. It is built from
/// whatever the operator configured in KEYS, then optionally confirmed against
/// each provider's own `/models` endpoint. A hardcoded list was the reason a
/// freshly added OpenRouter key never showed up in `pi models`.
class PiCore extends ChangeNotifier {
  PiCore({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  PiInstallState state = PiInstallState.absent;
  String installedVersion = '';
  String latestVersion = '';
  bool updateAvailable = false;
  String? lastError;
  DateTime? lastCheck;

  /// Model catalog: provider-seeded plus anything the provider confirmed.
  List<PiModelEntry> models = const [];
  String activeModel = '';

  /// Provider ids whose `/models` endpoint answered successfully.
  final Set<String> _probed = <String>{};

  /// Model ids confirmed by a live `/models` call, keyed by provider id.
  final Map<String, List<String>> _liveIds = <String, List<String>>{};

  List<String> get probedProviders => List.unmodifiable(_probed.toList());

  bool get nodeRequirementMet => false;

  String get statusLabel => switch (state) {
        PiInstallState.absent => 'not installed',
        PiInstallState.installing => 'installing…',
        PiInstallState.installed => 'pi $installedVersion',
        PiInstallState.failed => 'install failed',
      };

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// `pi install` — provision the agent core, then build the model catalog
  /// from the operator's vault.
  Future<void> install({List<Provider> providers = const []}) async {
    state = PiInstallState.installing;
    lastError = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      final latest = await fetchLatestVersion();
      installedVersion = latest ?? '1.3.0';
      latestVersion = installedVersion;
      updateAvailable = false;
      state = PiInstallState.installed;
      if (providers.isNotEmpty) seedFromProviders(providers);
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
    _liveIds.clear();
    _probed.clear();
    notifyListeners();
  }

  /// `pi update` — ask the npm registry what the newest release is.
  Future<String> update({bool apply = true, List<Provider> providers = const []}) async {
    final latest = await fetchLatestVersion();
    lastCheck = DateTime.now();
    if (latest == null) {
      lastError = 'registry unreachable';
      notifyListeners();
      return 'update check failed: ${lastError!}';
    }
    latestVersion = latest;
    if (providers.isNotEmpty) seedFromProviders(providers);
    if (installedVersion.isEmpty) {
      if (!apply) {
        notifyListeners();
        return 'latest is $latest (pi not installed)';
      }
      await install(providers: providers);
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
            Uri.parse(
                'https://registry.npmjs.org/${Uri.encodeComponent(kPiPackage)}/latest'),
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

  // ── Catalog ────────────────────────────────────────────────────────────

  /// Rebuild the catalog from the vault: every enabled LLM provider contributes
  /// its selected model plus its preset suggestions, plus anything a previous
  /// `/models` probe confirmed.
  ///
  /// Deduplicated on `providerId|id`, stable order (configured providers first,
  /// then the remaining presets ordered as the vault lists them).
  void seedFromProviders(List<Provider> providers) {
    final out = <PiModelEntry>[];
    final seen = <String>{};

    void add(PiModelEntry e) {
      if (e.id.trim().isEmpty) return;
      if (!seen.add('${e.providerId}|${e.id}')) return;
      out.add(e);
    }

    final llms = providers.where((p) => p.kind == ProviderKind.llm).toList()
      ..sort((a, b) {
        // Keyed providers first — those are the ones you can actually call.
        final ra = a.enabled && a.apiKey.trim().isNotEmpty ? 0 : 1;
        final rb = b.enabled && b.apiKey.trim().isNotEmpty ? 0 : 1;
        return ra.compareTo(rb);
      });

    for (final p in llms) {
      if (!p.enabled) continue;
      final vendor = p.id;
      // The model the operator typed in KEYS is the primary entry.
      if (p.model.trim().isNotEmpty) {
        add(PiModelEntry(
          p.model.trim(),
          vendor,
          _contextFor(p.id, p.model),
          _reasoningFor(p.id, p.model),
          providerId: p.id,
          free: ProviderPresets.freeModels.contains(p.model.trim()),
        ));
      }
      // Live ids come before guesses, because they are known to exist.
      for (final id in _liveIds[p.id] ?? const <String>[]) {
        add(PiModelEntry(
          id,
          vendor,
          _contextFor(p.id, id),
          _reasoningFor(p.id, id),
          providerId: p.id,
          free: ProviderPresets.freeModels.contains(id),
          live: true,
        ));
      }
      // Then the curated suggestions, so a fresh install is not empty.
      for (final id in ProviderPresets.suggestionsFor(p.id)) {
        add(PiModelEntry(
          id,
          vendor,
          _contextFor(p.id, id),
          _reasoningFor(p.id, id),
          providerId: p.id,
          free: ProviderPresets.freeModels.contains(id),
        ));
      }
    }

    // Fall back to the whole preset catalogue when nothing is configured, so
    // `/model` still explains what is possible before a key is pasted.
    if (out.isEmpty) {
      for (final p in ProviderPresets.all) {
        if (p.kind != ProviderKind.llm) continue;
        for (final id in ProviderPresets.suggestionsFor(p.id)) {
          add(PiModelEntry(
            id,
            p.id,
            _contextFor(p.id, id),
            _reasoningFor(p.id, id),
            providerId: p.id,
            free: ProviderPresets.freeModels.contains(id),
          ));
        }
      }
    }

    models = List.unmodifiable(out);
    if (activeModel.isEmpty && models.isNotEmpty) {
      activeModel = models.first.id;
    }
    notifyListeners();
  }

  /// Ask each ready provider for its real model list.
  ///
  /// This is a plain outbound HTTPS `GET {base}/models` using the operator's own
  /// key — the same request `pi models --refresh` makes on a desktop. Failures
  /// are recorded rather than thrown: a provider that does not implement
  /// `/models` still keeps its seeded entries.
  Future<PiProbeReport> probeProviders(
    List<Provider> providers, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final report = PiProbeReport();
    final targets = providers
        .where((p) => p.kind == ProviderKind.llm && p.enabled)
        .toList();

    for (final p in targets) {
      if (p.apiKey.trim().isEmpty) {
        report.skipped.add('${p.id} (no key)');
        continue;
      }
      final uri = Uri.parse('${_trim(p.baseUrl)}/models');
      try {
        final res = await _http.get(uri, headers: {
          'accept': 'application/json',
          if (p.baseUrl.contains('anthropic')) ...{
            'x-api-key': p.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          } else
            'authorization': 'Bearer ${p.apiKey.trim()}',
        }).timeout(timeout);

        if (res.statusCode >= 400) {
          report.failed[p.id] = 'HTTP ${res.statusCode}';
          continue;
        }
        final ids = _parseModelIds(res.body);
        if (ids.isEmpty) {
          report.failed[p.id] = 'no model ids in response';
          continue;
        }
        _liveIds[p.id] = ids;
        _probed.add(p.id);
        report.counts[p.id] = ids.length;
      } catch (e) {
        report.failed[p.id] = _short(e);
      }
    }

    seedFromProviders(providers);
    return report;
  }

  /// Extract model ids from the shapes that matter:
  /// OpenAI/Groq/OpenRouter `{data:[{id}]}`, Anthropic `{data:[{id}]}` and
  /// Ollama's `{models:[{name}]}`.
  static List<String> _parseModelIds(String body) {
    try {
      final j = jsonDecode(body);
      final out = <String>[];
      void take(Object? list, {String key = 'id'}) {
        if (list is! List) return;
        for (final e in list) {
          if (e is Map && e[key] is String) {
            final s = (e[key] as String).trim();
            if (s.isNotEmpty) out.add(s);
          } else if (e is String && e.trim().isNotEmpty) {
            out.add(e.trim());
          }
        }
      }

      if (j is Map) {
        take(j['data']);
        take(j['models'], key: 'name');
        final result = j['result'];
        if (result is Map) take(result['data']);
      } else if (j is List) {
        take(j);
      }
      // Stable, de-duplicated.
      return List<String>.from(out.toSet());
    } catch (_) {
      return const <String>[];
    }
  }

  /// Search the catalog. Empty query returns everything, in catalog order.
  ///
  /// Ranked: exact wire id, exact `provider/id`, prefix, then substring. That
  /// ordering is what makes `/model sonnet` land on Sonnet rather than on the
  /// first model that merely mentions it.
  List<PiModelEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return models;
    final scored = <(int, PiModelEntry)>[];
    for (final m in models) {
      final id = m.id.toLowerCase();
      final label = m.label.toLowerCase();
      final vendor = m.vendor.toLowerCase();
      int score;
      if (id == q || label == q) {
        score = 0;
      } else if (id.startsWith(q) || label.startsWith(q)) {
        score = 1;
      } else if (id.contains(q) || label.contains(q)) {
        score = 2;
      } else if (vendor.contains(q)) {
        score = 3;
      } else {
        continue;
      }
      scored.add((score, m));
    }
    scored.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.label.compareTo(b.$2.label);
    });
    return scored.map((e) => e.$2).toList();
  }

  /// Resolve whatever the operator typed into a concrete entry.
  ///
  /// Accepts a 1-based index, a bare wire id, a `provider/id` label, or a loose
  /// substring. Matching a label is preferred over a bare id so
  /// `openrouter/anthropic/claude-3.5-sonnet` cannot silently bind to a model
  /// that a different key would pay for.
  PiModelEntry? resolve(String arg) {
    final a = arg.trim();
    if (a.isEmpty) return null;
    final n = int.tryParse(a);
    if (n != null) {
      if (n < 1 || n > models.length) return null;
      return models[n - 1];
    }
    for (final m in models) {
      if (m.label.toLowerCase() == a.toLowerCase()) return m;
    }
    for (final m in models) {
      if (m.id.toLowerCase() == a.toLowerCase()) return m;
    }
    final hits = search(a);
    return hits.isEmpty ? null : hits.first;
  }

  /// `pi models [query]` — the catalog, filtered.
  Future<String> listModels({String query = ''}) async {
    if (models.isEmpty) return 'no models — add a key in KEYS, then `pi models --refresh`';
    final hits = search(query);
    if (hits.isEmpty) {
      return 'no model matching "$query" among ${models.length}';
    }
    final b = StringBuffer();
    for (final m in hits) {
      final mark = m.id == activeModel ? '*' : ' ';
      final flags = [
        if (m.free) 'free',
        if (m.live) 'live',
        if (m.reasoning) 'reasoning',
      ];
      b.writeln('$mark ${m.id.padRight(38).substring(0, 38.clamp(0, m.id.length + 3))}'
          '${m.vendor.padRight(13)}${m.contextLabel.padLeft(7)}'
          '${flags.isEmpty ? '' : '  ${flags.join(' · ')}'}');
    }
    b.write('${hits.length} of ${models.length} · select with /model <n> or /model <id>');
    return b.toString();
  }

  void setModel(String id) {
    if (id.isEmpty) return;
    activeModel = id;
    notifyListeners();
  }

  /// Select by 1-based catalog index.
  bool selectByIndex(int i) {
    if (i < 1 || i > models.length) return false;
    setModel(models[i - 1].id);
    return true;
  }

  /// The entry currently bound, if it is still in the catalog.
  PiModelEntry? get activeEntry {
    for (final m in models) {
      if (m.id == activeModel) return m;
    }
    return null;
  }

  /// Which vault provider should pay for [activeModel]?
  ///
  /// This is the linkage that makes a key usable: choosing a model also decides
  /// the endpoint.
  String? get activeProviderId => activeEntry?.providerId;

  // ── Persistence ────────────────────────────────────────────────────────

  String encodeCatalog() => jsonEncode({
        'active': activeModel,
        'live': _liveIds,
        'probed': _probed.toList(),
      });

  void loadCatalog(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      activeModel = (j['active'] ?? '').toString();
      final live = j['live'];
      if (live is Map) {
        _liveIds.clear();
        live.forEach((k, v) {
          if (v is List) {
            _liveIds[k.toString()] =
                v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
          }
        });
      }
      final probed = j['probed'];
      if (probed is List) {
        _probed
          ..clear()
          ..addAll(probed.map((e) => e.toString()));
      }
    } catch (_) {
      // A corrupt catalog is not fatal: it rebuilds from the vault.
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Best-effort context windows, only used for the `/context` percentage.
  /// Unknown ids report 0, which the UI renders as `—` rather than a lie.
  static int _contextFor(String providerId, String id) {
    final s = id.toLowerCase();
    if (s.contains('claude')) return 200;
    if (s.contains('gemini')) return 1000;
    if (s.contains('gpt-4.1')) return 1000;
    if (s.contains('gpt-4o') || s.contains('gpt-5')) return 400;
    if (s.contains('o4') || s.contains('o3')) return 200;
    if (s.contains('deepseek')) return 64;
    if (s.contains('qwen')) return 32;
    if (s.contains('llama-3.1-8b')) return 128;
    if (s.contains('llama')) return 128;
    if (s.contains('mixtral')) return 32;
    if (s.contains('mistral-large')) return 128;
    if (s.contains('glm')) return 128;
    return 0;
  }

  static bool _reasoningFor(String providerId, String id) {
    final s = id.toLowerCase();
    return s.contains('o3') ||
        s.contains('o4') ||
        s.contains('reason') ||
        s.contains('r1') ||
        s.contains('thinking') ||
        s.contains('gpt-5');
  }

  static String _trim(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

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

/// Outcome of a `/models` sweep, so the UI can be specific instead of vague.
class PiProbeReport {
  /// provider id → number of model ids returned.
  final Map<String, int> counts = <String, int>{};

  /// provider id → why it failed.
  final Map<String, String> failed = <String, String>{};

  /// Providers that could not be asked at all (no key).
  final List<String> skipped = <String>[];

  int get total => counts.values.fold(0, (a, b) => a + b);
  bool get ok => counts.isNotEmpty;

  String summary() {
    if (counts.isEmpty && failed.isEmpty && skipped.isEmpty) {
      return 'no LLM providers to probe';
    }
    final b = StringBuffer();
    if (counts.isNotEmpty) {
      b.writeln('confirmed ${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    }
    for (final e in failed.entries) {
      b.writeln('${e.key}: ${e.value}');
    }
    if (skipped.isNotEmpty) b.writeln('skipped ${skipped.join(', ')}');
    return b.toString().trimRight();
  }
}
