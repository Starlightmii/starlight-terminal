import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/model_client.dart';
import '../core/pi_commands.dart';
import '../core/pi_core.dart';
import '../core/providers.dart';
import '../core/session_store.dart';
import '../state/studio_controller.dart';

/// How a line in the pi transcript should be rendered.
enum PiLineKind { prompt, reply, thinking, tool, sys, err, cmd, info }

@immutable
class PiLine {
  const PiLine(this.text, this.kind, this.at);
  final String text;
  final PiLineKind kind;
  final DateTime at;

  PiLine copyWith({String? text, PiLineKind? kind}) =>
      PiLine(text ?? this.text, kind ?? this.kind, at);
}

/// Thinking effort, mirroring pi's `/thinking`.
enum PiThinking { off, low, medium, high }

extension PiThinkingLabel on PiThinking {
  String get label => switch (this) {
        PiThinking.off => 'off',
        PiThinking.low => 'low',
        PiThinking.medium => 'medium',
        PiThinking.high => 'high',
      };

  String get instruction => switch (this) {
        PiThinking.off => 'Answer directly. No visible reasoning.',
        PiThinking.low => 'Think briefly before answering.',
        PiThinking.medium =>
          'Reason carefully before answering. Keep the reasoning short.',
        PiThinking.high =>
          'Reason thoroughly. Enumerate options before committing to an answer.',
      };
}

/// Owns the pi terminal: transcript, history, slash commands, skills and the
/// streaming turn.
///
/// This lives in the controller rather than in a widget so switching tabs does
/// not destroy the session — a terminal that forgets everything when you look
/// away is not a terminal.
class PiSession extends ChangeNotifier {
  PiSession(this.studio);

  final StudioController studio;

  final List<PiLine> _lines = <PiLine>[];
  List<PiLine> get lines => List.unmodifiable(_lines);

  final List<String> _history = <String>[];
  List<String> get history => List.unmodifiable(_history);

  bool _running = false;
  bool get running => _running;

  PiThinking thinking = PiThinking.medium;

  String? _sessionId;
  String? get sessionId => _sessionId;

  /// Live suggestion list for the composer popup.
  List<String> _suggestions = const [];
  List<String> get suggestions => _suggestions;

  /// Streaming reply currently being appended to.
  int _streamIndex = -1;

  int _turnCount = 0;
  int get turnCount => _turnCount;

  static const String _systemBase =
      'You are pi, a coding agent running inside Starlight Terminal on an '
      'Android device. You answer in plain text: no markdown tables, no '
      'LaTeX, no emoji headers. Keep answers tight and concrete. If you are '
      'unsure, say so in one sentence and name what would resolve it.';

  // ══════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════

  void boot() {
    if (_lines.isNotEmpty) return;
    _append(
      'pi ${studio.pi.installedVersion} · ${studio.pi.models.length} models · '
      '${studio.agentProvider?.id ?? 'no key'}',
      PiLineKind.sys,
    );
    _append(
      'Type a prompt, or / for commands, ! for a shell command, @ for a file.',
      PiLineKind.sys,
    );
    _append('Skills: ${kPiSkills.map((s) => s.name).join(', ')}', PiLineKind.info);
    _seedSkillsIntoVfs();
    _append('', PiLineKind.info);
  }

  void _seedSkillsIntoVfs() {
    final fs = studio.fs;
    for (final s in kPiSkills) {
      fs.write(
        '/home/user/.pi/skills/${s.name}.md',
        '# ${s.name}\n\n${s.summary}\n\n${s.prompt}\n',
      );
    }
    fs.write(
      '/home/user/.pi/commands.txt',
      kPiCommands.map((c) => '${c.usage.padRight(30)}${c.summary}').join('\n'),
    );
  }

  void _append(String text, PiLineKind kind) {
    _lines.add(PiLine(text, kind, DateTime.now()));
    if (_lines.length > 900) _lines.removeRange(0, _lines.length - 900);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Composer support
  // ══════════════════════════════════════════════════════════════════════

  /// Recompute the popup suggestions for the current input.
  void onInputChanged(String value) {
    final v = value.trimLeft();
    List<String> next;

    if (v.startsWith('/skill:')) {
      next = completeSkill(v).map((s) => '/skill:${s.name}  ${s.summary}').toList();
    } else if (v.startsWith('/')) {
      next = completeCommand(v).map((c) => '${c.usage}  ${c.summary}').toList();
    } else {
      next = const [];
    }

    if (!listEquals(next, _suggestions)) {
      _suggestions = next;
      notifyListeners();
    }
  }

  /// Tab completion. Returns the text the field should now contain.
  String complete(String value) {
    final v = value.trimLeft();
    if (v.startsWith('/skill:')) {
      final hits = completeSkill(v);
      if (hits.length == 1) return '/skill:${hits.first.name} ';
      return value;
    }
    if (v.startsWith('/')) {
      final hits = completeCommand(v);
      if (hits.isEmpty) return value;
      if (hits.length == 1) {
        final hint = hits.first.argHint;
        return hint == null ? '${hits.first.name} ' : '${hits.first.name} ';
      }
      // Longest common prefix, so repeated Tab narrows rather than rewrites.
      var prefix = hits.first.name;
      for (final c in hits.skip(1)) {
        var i = 0;
        while (i < prefix.length &&
            i < c.name.length &&
            prefix[i] == c.name[i]) {
          i++;
        }
        prefix = prefix.substring(0, i);
      }
      return prefix;
    }
    return value;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Submit
  // ══════════════════════════════════════════════════════════════════════

  Future<void> submit(String raw) async {
    final input = raw.trim();
    if (input.isEmpty || _running) return;
    _history.add(input);
    _suggestions = const [];

    // `pi /model`, `pi models`, `pi --help` and friends are shell lines, not
    // prompts. Treating them as prose is why "pi /commands" looked broken: the
    // text went to the model, which answered about pi instead of running it.
    final lowered = input.toLowerCase();
    if (lowered == 'pi' ||
        lowered.startsWith('pi ') ||
        lowered == 'commands' ||
        lowered == '/commands') {
      final rest = lowered == 'commands' || lowered == '/commands'
          ? '/help'
          : input.length > 3
              ? input.substring(3).trim()
              : '';
      _append('❯ $input', PiLineKind.cmd);
      if (rest.isEmpty) {
        _append(_piShellSummary(), PiLineKind.sys);
        return;
      }
      final normalised = rest.startsWith('/') ? rest : '/$rest';
      // A `pi <sub>` that is not a pi slash command is a shell invocation.
      if (_isPiCommand(normalised)) {
        await _slash(normalised);
      } else {
        await _shell(rest);
      }
      return;
    }

    if (input.startsWith('/') && !input.startsWith('/skill:')) {
      _append('❯ $input', PiLineKind.cmd);
      await _slash(input);
      return;
    }
    if (input.startsWith('/skill:')) {
      _append('❯ $input', PiLineKind.cmd);
      await _skillCommand(input.substring(7).trim());
      return;
    }
    if (input.startsWith('!')) {
      _append('❯ $input', PiLineKind.cmd);
      await _shell(input);
      return;
    }

    _append('❯ $input', PiLineKind.prompt);
    await _agentTurn(input);
  }

  /// Is this `/<name>` a pi command we actually implement?
  bool _isPiCommand(String slash) {
    final space = slash.indexOf(' ');
    final name = (space < 0 ? slash : slash.substring(0, space)).toLowerCase();
    return kPiCommands.any((c) => c.name == name) ||
        name == '/models' ||
        name == '/use' ||
        name == '/keys' ||
        name == '/commands' ||
        name == '/install' ||
        name == '/logout';
  }

  String _piShellSummary() {
    return 'pi ${studio.pi.installedVersion.isEmpty ? '(not installed)' : studio.pi.installedVersion}'
        '\n'
        '  pi status | models [query] | models --refresh | model <n|id>\n'
        '  pi install | update | version | --help\n'
        'Inside this transcript you can also type the slash form directly:\n'
        '  ${kPiCommands.map((c) => c.name).join('  ')}';
  }

  // ══════════════════════════════════════════════════════════════════════
  // Shell passthrough (`!cmd` / `!!cmd`)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _shell(String input) async {
    final silent = input.startsWith('!!');
    final cmd = silent ? input.substring(2).trim() : input.substring(1).trim();
    if (cmd.isEmpty) {
      _append('shell: nothing to run', PiLineKind.err);
      return;
    }

    // `pi update` and `pi models --refresh` do real network work. They used to
    // be fired with `unawaited()` so their result never reached the log — the
    // command appeared to do nothing. Await them and stream a waiting line.
    final slow = studio.isSlowShell(cmd);
    if (slow) {
      _running = true;
      _append('… ${cmd.split(' ').join(' ')}', PiLineKind.sys);
      notifyListeners();
    }

    String? out;
    try {
      out = await studio.shellExecAsync(cmd);
    } finally {
      if (slow) {
        _running = false;
        notifyListeners();
      }
    }

    if (out == null) {
      _append(
        'shell: `$cmd` is not a builtin. Try ls, cd, pwd, cat, echo, mkdir, '
        'touch, rm, df, pi, or `man` for the full list.',
        PiLineKind.err,
      );
      return;
    }
    if (out.isEmpty) {
      _append('(no output)', PiLineKind.sys);
    } else {
      for (final l in out.split('\n')) {
        _append(l, PiLineKind.tool);
      }
    }
    if (!silent) {
      _lastShellOutput = out;
      _append(
        '(output kept in context — send a prompt to discuss it)',
        PiLineKind.sys,
      );
    }
  }

  String _lastShellOutput = '';

  // ══════════════════════════════════════════════════════════════════════
  // Agent turn
  // ══════════════════════════════════════════════════════════════════════

  /// Expand `@path` references in a prompt into fenced file contents.
  String _expandRefs(String prompt) {
    final matches = RegExp(r'@([\w./\-~]+)').allMatches(prompt);
    if (matches.isEmpty) return prompt;
    final buf = StringBuffer(prompt);
    buf.write('\n\n--- referenced files ---');
    for (final m in matches) {
      final path = m.group(1)!;
      final body = studio.fs.read(path);
      if (body == null) {
        buf.write('\n## $path\n(no such file)');
      } else {
        final clipped = body.length > 4000 ? '${body.substring(0, 4000)}\n…' : body;
        buf.write('\n## $path\n$clipped');
      }
    }
    return buf.toString();
  }

  Future<void> _agentTurn(String raw) async {
    final provider = studio.agentProvider;
    if (provider == null) {
      _append(
        'No usable LLM key. Add one in KEYS — pi runs on your own key, '
        'there is no bundled model.',
        PiLineKind.err,
      );
      return;
    }

    // Ensure a session exists so memories and the SESSIONS tab stay in sync.
    var session = studio.sessions.ensurePi(model: studio.pi.activeModel);
    _sessionId ??= session.id;
    studio.sessions.setActive(session.id);
    studio.sessions.appendMessage(
      session.id,
      SessionMessage(role: 'you', text: raw, at: DateTime.now()),
      remember: true,
    );

    final prompt = _expandRefs(raw);
    final messages = <Map<String, String>>[];
    for (final m in _recentMessages(session)) {
      if (m.isError) continue;
      messages.add({
        'role': m.role == 'you' ? 'user' : 'assistant',
        'content': m.text,
      });
    }
    if (messages.isEmpty || messages.last['content'] != prompt) {
      messages.add({'role': 'user', 'content': prompt});
    }

    if (_lastShellOutput.isNotEmpty) {
      messages.insert(0, {
        'role': 'user',
        'content': 'Last shell output you may refer to:\n$_lastShellOutput',
      });
      _lastShellOutput = '';
    }

    _running = true;
    _streamIndex = _lines.length;
    _append('', PiLineKind.reply);
    notifyListeners();

    final buf = StringBuffer();
    String? failure;
    try {
      await for (final c in studio.models.stream(
        provider: provider,
        messages: messages,
        model: studio.pi.activeModel.isEmpty ? null : studio.pi.activeModel,
        system: '$_systemBase\n\n${thinking.instruction}',
      )) {
        switch (c.kind) {
          case ChunkKind.text:
            buf.write(c.text);
            _replaceStream(buf.toString(), PiLineKind.reply);
          case ChunkKind.thinking:
            if (thinking != PiThinking.off) {
              _append(c.text, PiLineKind.thinking);
            }
          case ChunkKind.error:
            failure = c.text;
            _replaceStream(c.text, PiLineKind.err);
            studio.appLog.error(c.text, scope: 'pi');
          case ChunkKind.tool:
          case ChunkKind.done:
            break;
        }
      }
    } catch (e) {
      failure = '$e';
      _replaceStream(failure, PiLineKind.err);
    } finally {
      _running = false;
      _streamIndex = -1;
      _turnCount++;
      notifyListeners();
    }

    final reply = buf.toString().trim();
    if (failure == null && reply.isNotEmpty) {
      studio.sessions.appendMessage(
        session.id,
        SessionMessage(role: 'pi', text: reply, at: DateTime.now()),
        remember: true,
      );
      studio.appLog.info('pi turn · ${reply.length} chars', scope: 'pi');
    }
  }

  void _replaceStream(String text, PiLineKind kind) {
    if (_streamIndex < 0 || _streamIndex >= _lines.length) {
      _append(text, kind);
      return;
    }
    _lines[_streamIndex] = _lines[_streamIndex].copyWith(text: text, kind: kind);
    notifyListeners();
  }

  List<SessionMessage> _recentMessages(ChatSession s) {
    final max = thinking == PiThinking.high ? 18 : 12;
    final msgs = s.messages;
    return msgs.length > max ? msgs.sublist(msgs.length - max) : msgs;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Skills
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _skillCommand(String rest) async {
    final parts = rest.split(RegExp(r'\s+'));
    final name = parts.first;
    final args = parts.skip(1).join(' ').trim();
    final skill = skillByName(name);
    if (skill == null) {
      _append(
        'no such skill: $name. Available: '
        '${kPiSkills.map((s) => s.name).join(', ')}',
        PiLineKind.err,
      );
      return;
    }
    _append('▸ skill ${skill.name} · ${skill.summary}', PiLineKind.info);
    final prompt = args.isEmpty
        ? '${skill.prompt}\n\n(No subject given — apply this to our '
            'conversation so far.)'
        : '${skill.prompt}\n\nSubject:\n$args';
    await _agentTurn(prompt);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Slash commands
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _slash(String input) async {
    final space = input.indexOf(' ');
    final name = (space < 0 ? input : input.substring(0, space)).toLowerCase();
    final arg = space < 0 ? '' : input.substring(space + 1).trim();
    final pi = studio.pi;

    switch (name) {
      // ── help / status ──────────────────────────────────────────────────
      case '/help':
        _printHelp();
      case '/status':
        _append(
          'state      ${pi.statusLabel}\n'
          'installed  ${pi.installedVersion.isEmpty ? '—' : pi.installedVersion}\n'
          'latest     ${pi.latestVersion.isEmpty ? '—' : pi.latestVersion}\n'
          'model      ${pi.activeModel.isEmpty ? '—' : pi.activeModel}\n'
          'thinking   ${thinking.label}\n'
          'provider   ${studio.agentProvider?.id ?? 'none configured'}\n'
          'session    ${_sessionId ?? '—'}\n'
          'turns      $_turnCount',
          PiLineKind.sys,
        );
      case '/version':
        _append(pi.versionLine(), PiLineKind.sys);

      // ── models ─────────────────────────────────────────────────────────
      case '/model':
        await _modelCommand(arg);
      case '/models':
        await _modelsCommand(arg);
      case '/use':
        await _modelCommand(arg);
      case '/keys':
        _keysCommand(arg);
      case '/commands':
        _printHelp();
      case '/install':
        await _installCommand();
      case '/net':
        _netCheck();
      case '/thinking':
        if (arg.isEmpty) {
          _append(
            'thinking is ${thinking.label}. levels: off, low, medium, high',
            PiLineKind.sys,
          );
        } else {
          final lvl = PiThinking.values
              .where((t) => t.label == arg.toLowerCase())
              .toList();
          if (lvl.isEmpty) {
            _append('usage: /thinking off|low|medium|high', PiLineKind.err);
          } else {
            thinking = lvl.first;
            _append('thinking → ${thinking.label}', PiLineKind.info);
            notifyListeners();
          }
        }
      case '/scoped-models':
        _append(
          'Scoped cycling uses the installed catalog. Run /model to pick one, '
          '/models to list them.',
          PiLineKind.sys,
        );

      // ── auth ───────────────────────────────────────────────────────────
      case '/login':
        _keysCommand(arg);
      case '/logout':
        final id = arg.trim();
        if (id.isEmpty) {
          _append(
            'usage: /logout <provider>  (e.g. /logout openrouter)\n'
            'Keys live in the vault; the KEYS tab removes them too.',
            PiLineKind.sys,
          );
        } else {
          studio.clearKey(id);
          _append('cleared the key for $id', PiLineKind.info);
        }
      case '/settings':
        _keysCommand('');

      // ── sessions ───────────────────────────────────────────────────────
      case '/new':
        _newSession();
      case '/resume':
        _resumeSession();
      case '/session':
        _sessionInfo();
      case '/name':
        _nameSession(arg);
      case '/tree':
        _printTree();
      case '/fork':
        _forkSession(arg);
      case '/clone':
        _cloneSession();
      case '/compact':
        _compact(arg);
      case '/context':
        _context();
      case '/import':
        _append(
          'import expects a JSONL path from a desktop pi install. '
          'Use /export to write one here, then cat it in CONSOLE.',
          PiLineKind.sys,
        );

      // ── share ──────────────────────────────────────────────────────────
      case '/copy':
        await _copyLast();
      case '/export':
        _exportSession(arg);
      case '/share':
        _shareDigest();
      case '/bug':
        _bugReport(arg);

      // ── runtime ────────────────────────────────────────────────────────
      case '/skills':
        _listSkills();
      case '/skill':
        _append(
          'use /skill:<name> — e.g. /skill:research what is rust borrow checking',
          PiLineKind.sys,
        );
      case '/reload':
        _seedSkillsIntoVfs();
        _append('reloaded skills, templates and command index', PiLineKind.info);
      case '/hotkeys':
        _printHotkeys();
      case '/changelog':
        _append(
          'Starlight Terminal 1.0.0\n'
          ' · pi command surface rewritten to match pi.dev\n'
          ' · 27 background effects with a spectrum colour ramp\n'
          ' · cursor controller: arrows, home/end, tab completion\n'
          ' · multi-user accounts with per-device hashing',
          PiLineKind.sys,
        );
      case '/update':
        _append('checking registry.npmjs.org…', PiLineKind.sys);
        final msg = await pi.update();
        studio.appLog.info(msg, scope: 'pi');
        _append(msg, PiLineKind.info);
      case '/debug':
        _debugDump();
      case '/clear':
        clear();
      case '/quit':
        _append(
          'session stays open — closing it would lose the transcript. '
          'Use /new for a fresh one.',
          PiLineKind.sys,
        );
      default:
        _append(
          'unknown command $name — /help lists all '
          '${kPiCommands.length}.',
          PiLineKind.err,
        );
    }
  }

  void _printHelp() {
    final b = StringBuffer();
    for (final group in PiCommandGroup.values) {
      b.writeln('─ ${kPiGroupLabel[group]} ${'─' * 24}');
      for (final c in kPiCommands.where((c) => c.group == group)) {
        b.writeln('  ${c.usage.padRight(28)}${c.summary}');
      }
      b.writeln();
    }
    b.writeln('─ SKILLS ${'─' * 34}');
    for (final s in kPiSkills) {
      b.writeln('  ${'/skill:${s.name}'.padRight(28)}${s.summary}');
    }
    b.writeln();
    b.writeln('─ PREFIXES ${'─' * 32}');
    b.writeln('  !cmd                          run a shell builtin');
    b.writeln('  !!cmd                         run without keeping output');
    b.writeln('  @path                         attach a file to the prompt');
    _append(b.toString().trimRight(), PiLineKind.sys);
  }

  Future<void> _modelCommand(String arg) async {
    final pi = studio.pi;
    if (pi.models.isEmpty) {
      _append(
        'no model catalog yet. Add a key in KEYS — every enabled LLM provider '
        'contributes its models — then /models --refresh to confirm ids.',
        PiLineKind.err,
      );
      return;
    }
    if (arg.isEmpty || arg == 'list') {
      _append(await _catalogBody(''), PiLineKind.sys);
      return;
    }
    final hit = pi.resolve(arg);
    if (hit == null) {
      final loose = pi.search(arg);
      _append(
        'no model matching "$arg" among ${pi.models.length}'
        '${loose.isEmpty ? '' : '\nclosest: ${loose.take(5).map((m) => m.id).join(', ')}'}',
        PiLineKind.err,
      );
      return;
    }
    pi.setModel(hit.id);
    final s = studio.sessions.ensurePi(model: pi.activeModel);
    s.piModel = pi.activeModel;
    studio.sessions.touch();
    studio.appLog.info('pi model → ${hit.label}', scope: 'pi');
    _append(
      'model → ${hit.id}\n'
      'provider ${hit.providerId.isEmpty ? (studio.agentProvider?.id ?? 'none') : hit.providerId}'
      ' · ctx ${hit.contextLabel}'
      '${hit.reasoning ? ' · reasoning' : ''}${hit.free ? ' · free' : ''}',
      PiLineKind.info,
    );
  }

  /// `/models [query]` — list or search; `--refresh` asks the providers.
  Future<void> _modelsCommand(String arg) async {
    final refresh = arg.contains('--refresh') || arg.contains('-r');
    final query = arg
        .split(RegExp(r'\s+'))
        .where((a) => a.isNotEmpty && a != '--refresh' && a != '-r')
        .join(' ');
    if (refresh) {
      if (studio.agentProviders.isEmpty) {
        _append(
          'nothing to refresh — no LLM key is configured. Add one in KEYS.',
          PiLineKind.err,
        );
        return;
      }
      _running = true;
      _append(
        'asking ${studio.agentProviders.map((p) => p.id).join(', ')} for /models…',
        PiLineKind.sys,
      );
      notifyListeners();
      final report = await studio.pi.probeProviders(studio.providers);
      _running = false;
      notifyListeners();
      studio.appLog.info('pi models refresh · ${report.summary()}', scope: 'pi');
      _append(report.summary(), report.ok ? PiLineKind.info : PiLineKind.err);
    }
    _append(await _catalogBody(query), PiLineKind.sys);
  }

  Future<String> _catalogBody(String query) async {
    final pi = studio.pi;
    final hits = pi.search(query);
    if (hits.isEmpty) {
      return query.isEmpty
          ? 'catalog is empty — add a key in KEYS'
          : 'no model matching "$query" among ${pi.models.length}';
    }
    final b = StringBuffer();
    if (query.isEmpty) {
      final providers = pi.models.map((m) => m.providerId).toSet();
      b.writeln('catalog · ${pi.models.length} models · '
          '${providers.length} providers'
          '${pi.probedProviders.isEmpty ? ' · ids unconfirmed (/models --refresh)' : ' · confirmed: ${pi.probedProviders.join(', ')}'}');
    } else {
      b.writeln('search "$query" · ${hits.length} of ${pi.models.length}');
    }
    for (var i = 0; i < hits.length; i++) {
      final m = hits[i];
      final mark = m.id == pi.activeModel ? '*' : ' ';
      final flags = [
        if (m.free) 'free',
        if (m.live) 'live',
        if (m.reasoning) 'reason',
      ];
      b.writeln('$mark ${(i + 1).toString().padLeft(3)}. '
          '${m.id.padRight(34)}${m.providerId.padRight(13)}'
          '${m.contextLabel.padLeft(6)}'
          '${flags.isEmpty ? '' : '  ${flags.join(' ')}'}');
    }
    b.write('pick with /model <n> or /model <id>');
    return b.toString();
  }

  /// `/keys` — what the vault actually holds, and what pi can therefore use.
  void _keysCommand(String arg) {
    final all = studio.providers.where((p) => p.kind == ProviderKind.llm).toList();
    final ready = studio.agentProviders;
    final b = StringBuffer()
      ..writeln('key vault · ${ready.length} of ${all.length} LLM providers ready');
    for (final p in all) {
      final ok = p.ready && p.looksPlausible;
      final count = studio.pi.models.where((m) => m.providerId == p.id).length;
      b.writeln('${ok ? '●' : '○'} ${p.id.padRight(14)}'
          '${(ok ? p.maskedKey : 'no key').padRight(20)}'
          '${count.toString().padLeft(3)} models  ${p.model}');
    }
    b.write(
      'pi routes turns through ${studio.agentProvider?.id ?? 'nothing yet'}. '
      'Add or replace keys in the KEYS tab.',
    );
    _append(b.toString(), PiLineKind.sys);
    if (arg.trim().isNotEmpty) {
      final p = studio.byId(arg.trim());
      if (p != null) {
        _append(
          '${p.label}: base ${p.baseUrl}${p.baseUrl.isEmpty ? '' : '/chat/completions'}\n'
          'model ${p.model.isEmpty ? 'unset' : p.model} · max ${p.maxTokens} tokens',
          PiLineKind.sys,
        );
      }
    }
  }

  /// `/install` — provision the core and rebuild the catalog from the vault.
  Future<void> _installCommand() async {
    _running = true;
    _append('installing pi…', PiLineKind.sys);
    notifyListeners();
    await studio.pi.install(providers: studio.providers);
    _running = false;
    notifyListeners();
    final pi = studio.pi;
    if (pi.state == PiInstallState.failed) {
      _append('install failed: ${pi.lastError ?? 'unknown'}', PiLineKind.err);
      return;
    }
    _append(
      'pi ${pi.installedVersion} ready · ${pi.models.length} models from '
      '${pi.models.map((m) => m.providerId).toSet().length} providers',
      PiLineKind.info,
    );
  }

  /// `/net` — why a turn failed, named precisely.
  void _netCheck() {
    final ready = studio.agentProviders;
    final b = StringBuffer()
      ..writeln('network self-check')
      ..writeln('providers ready   ${ready.isEmpty ? 'none' : ready.map((p) => p.id).join(', ')}')
      ..writeln('platform          ${kIsWeb ? 'web (browser CORS applies)' : 'native' }')
      ..writeln('routing           ${studio.models.runtimeType} · direct HTTPS, no broker');
    if (ready.isNotEmpty) {
      final p = ready.first;
      b.writeln('endpoint          ${p.chatEndpoint}');
      if (kIsWeb && p.baseUrl.contains('anthropic')) {
        b.writeln('warning           Anthropic sends no CORS headers — use '
            'Android or an OpenAI-compatible provider on web.');
      }
    }
    b.writeln();
    b.writeln('if a turn fails with "network unreachable":');
    b.writeln(' · the release APK needs android.permission.INTERNET');
    b.writeln(' · a browser build needs the provider to allow CORS');
    b.writeln(' · Ollama on localhost is unreachable from a phone');
    _append(b.toString().trimRight(), PiLineKind.sys);
  }

  void _newSession() {
    final s = studio.sessions.create(
      kind: SessionKind.pi,
      title: 'pi session',
      piModel: studio.pi.activeModel,
    );
    studio.sessions.setActive(s.id);
    _sessionId = s.id;
    clear();
    studio.appLog.info('pi new session ${s.id}', scope: 'pi');
    _append('new session ${s.id}', PiLineKind.info);
    boot();
  }

  void _resumeSession() {
    final all = studio.sessions.byKind(SessionKind.pi);
    if (all.isEmpty) {
      _append('no saved pi sessions', PiLineKind.sys);
      return;
    }
    final b = StringBuffer('saved pi sessions\n');
    for (final s in all.take(12)) {
      final mark = s.id == _sessionId ? '*' : ' ';
      b.writeln('$mark ${s.id}  ${s.messageCount.toString().padLeft(3)} msg  '
          '${s.ageLabel.padLeft(4)}  ${s.title}');
    }
    b.write('open the SESSIONS tab to switch, or /fork <n> to branch.');
    _append(b.toString(), PiLineKind.sys);
  }

  void _sessionInfo() {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    _append(
      'id         ${s.id}\n'
      'name       ${s.title}\n'
      'created    ${s.createdAt.toLocal().toString().substring(0, 19)}\n'
      'messages   ${s.messageCount}\n'
      'model      ${s.piModel.isEmpty ? '—' : s.piModel}\n'
      'in / out   ${s.tokensIn} / ${s.tokensOut} tokens\n'
      'tool calls ${s.toolCalls}\n'
      'errors     ${s.errorCount}\n'
      'memory     ${studio.memory.all.length} facts tracked',
      PiLineKind.sys,
    );
  }

  void _nameSession(String arg) {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    if (arg.isEmpty) {
      _append('session name: ${s.title}', PiLineKind.sys);
      return;
    }
    s.title = arg;
    studio.sessions.touch();
    _append('session renamed → $arg', PiLineKind.info);
  }

  void _printTree() {
    final s = _current();
    if (s == null || s.messages.isEmpty) {
      _append('session is empty', PiLineKind.sys);
      return;
    }
    final b = StringBuffer('session tree\n');
    for (var i = 0; i < s.messages.length; i++) {
      final m = s.messages[i];
      final line = m.text.replaceAll('\n', ' ');
      final cut = line.length > 54 ? '${line.substring(0, 54)}…' : line;
      b.writeln('${i.toString().padLeft(3)} ├ ${m.glyph} $cut');
    }
    b.write('fork any point with /fork <n>');
    _append(b.toString(), PiLineKind.sys);
  }

  void _forkSession(String arg) {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    final at = int.tryParse(arg);
    if (at == null || at < 0 || at >= s.messages.length) {
      _append('usage: /fork <message-index> (see /tree)', PiLineKind.err);
      return;
    }
    final fork = studio.sessions.create(
      kind: SessionKind.pi,
      title: '${s.title} · fork@$at',
      piModel: s.piModel,
      tags: const ['fork'],
    );
    for (var i = 0; i <= at; i++) {
      final m = s.messages[i];
      fork.append(m);
    }
    studio.sessions.setActive(fork.id);
    studio.sessions.touch();
    _sessionId = fork.id;
    _append('forked at $at → ${fork.id} (${fork.messageCount} messages)',
        PiLineKind.info);
  }

  void _cloneSession() {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    final clone = studio.sessions.create(
      kind: SessionKind.pi,
      title: '${s.title} · clone',
      piModel: s.piModel,
      tags: const ['clone'],
    );
    for (final m in s.messages) {
      clone.append(m);
    }
    studio.sessions.setActive(clone.id);
    studio.sessions.touch();
    _sessionId = clone.id;
    _append('cloned → ${clone.id} (${clone.messageCount} messages)',
        PiLineKind.info);
  }

  void _compact(String instructions) {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    if (s.messages.length <= 6) {
      _append('nothing to compact — session is already short', PiLineKind.sys);
      return;
    }
    // Deterministic compaction: keep the tail, replace the head with a
    // synthetic marker. A model-summarised compaction would cost a call and
    // silently change the record, which is worse than being explicit.
    final keep = s.messages.sublist(s.messages.length - 6);
    final dropped = s.messages.length - keep.length;
    s.messages
      ..clear()
      ..add(SessionMessage(
        role: 'sys',
        text: '[compacted $dropped earlier messages'
            '${instructions.isEmpty ? '' : ': $instructions'}]',
        at: DateTime.now(),
      ))
      ..addAll(keep);
    studio.sessions.touch();
    studio.appLog.info('pi compact · $dropped dropped', scope: 'pi');
    _append('compacted $dropped messages, kept the last ${keep.length}',
        PiLineKind.info);
  }

  void _context() {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    final chars = s.messages.fold<int>(0, (a, m) => a + m.text.length);
    final tokens = (chars / 4).round();
    final model = studio.pi.models
        .where((m) => m.id == studio.pi.activeModel)
        .toList();
    final window = model.isEmpty ? 128 : model.first.context;
    final pct = window == 0 ? 0 : (tokens / (window * 1000) * 100);
    _append(
      'context      ~$tokens tokens ($chars chars)\n'
      'window       $window k for '
      '${studio.pi.activeModel.isEmpty ? 'default' : studio.pi.activeModel}\n'
      'used         ${pct.toStringAsFixed(1)}%\n'
      'messages     ${s.messageCount}\n'
      '${pct > 60 ? 'run /compact to make room' : 'headroom is fine'}',
      PiLineKind.sys,
    );
  }

  // ── share & export ─────────────────────────────────────────────────────

  Future<void> _copyLast() async {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    for (var i = s.messages.length - 1; i >= 0; i--) {
      final m = s.messages[i];
      if (m.role == 'pi' && m.text.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: m.text));
        _append('copied ${m.text.length} chars to the clipboard',
            PiLineKind.info);
        return;
      }
    }
    _append('no assistant message to copy', PiLineKind.sys);
  }

  void _exportSession(String arg) {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    final path = arg.isEmpty ? '/home/user/pi-export-${s.id}.jsonl' : arg;
    final b = StringBuffer();
    for (final m in s.messages) {
      b.writeln(jsonEncode({
        'role': m.role,
        'at': m.at.toIso8601String(),
        'text': m.text,
        if (m.toolName != null) 'tool': m.toolName,
        if (m.isError) 'error': true,
      }));
    }
    studio.fs.write(path, b.toString());
    _append(
      'exported ${s.messages.length} messages → $path\n'
      'inspect with: cat $path',
      PiLineKind.info,
    );
  }

  void _shareDigest() {
    final s = _current();
    if (s == null) {
      _append('no active session', PiLineKind.sys);
      return;
    }
    // No upload: pi's /share goes through Radius or a GitHub gist, neither of
    // which exists here. Produce a digest the operator can paste instead.
    final b = StringBuffer()
      ..writeln('# Starlight pi session ${s.id}')
      ..writeln('model: ${s.piModel.isEmpty ? 'default' : s.piModel}')
      ..writeln('messages: ${s.messageCount}')
      ..writeln();
    for (final m in s.messages) {
      if (m.role == 'sys') continue;
      final tag = m.role == 'you' ? 'User' : 'Pi';
      b.writeln('**$tag:** ${m.text.trim()}');
      b.writeln();
    }
    unawaited(Clipboard.setData(ClipboardData(text: b.toString())));
    _append(
      'digest (${b.length} chars) copied to the clipboard.\n'
      'There is no upload endpoint here — sharing is a local copy on purpose.',
      PiLineKind.info,
    );
  }

  void _bugReport(String description) {
    final b = StringBuffer()
      ..writeln('--- bug report ---')
      ..writeln('pi        ${studio.pi.installedVersion}')
      ..writeln('model     ${studio.pi.activeModel}')
      ..writeln('provider  ${studio.agentProvider?.id ?? 'none'}')
      ..writeln('thinking  ${thinking.label}')
      ..writeln('session   ${_sessionId ?? '—'}')
      ..writeln('turns     $_turnCount')
      ..writeln('description: '
          '${description.isEmpty ? '(none given)' : description}')
      ..writeln('recent transcript:');
    for (final l in _lines.reversed.take(12).toList().reversed) {
      b.writeln('  [${l.kind.name}] ${l.text.replaceAll('\n', ' ')}');
    }
    studio.fs.write('/home/user/pi-bug.txt', b.toString());
    _append('wrote /home/user/pi-bug.txt — cat it, then copy what you need',
        PiLineKind.info);
  }

  // ── runtime ────────────────────────────────────────────────────────────

  void _listSkills() {
    final b = StringBuffer('skills (${kPiSkills.length}) · ~/.pi/skills\n');
    for (final s in kPiSkills) {
      b.writeln('  ${s.name.padRight(12)}${s.summary}');
    }
    b.write('run one with /skill:<name> <subject>');
    _append(b.toString(), PiLineKind.sys);
  }

  void _printHotkeys() {
    _append(
      'on-screen bar   ↑ ↓ ← →  home  end  tab  ^C\n'
      'tab             complete a /command or /skill:name\n'
      'enter           send; ↑ history recalls last input\n'
      '^C              abandon the current turn\n'
      '^L              clear the transcript\n'
      '^U              clear the input line\n'
      '^A / ^E         jump to start / end of the line',
      PiLineKind.sys,
    );
  }

  void _debugDump() {
    _append(
      'state       ${studio.pi.state.name}\n'
      'models      ${studio.pi.models.length}\n'
      'active      ${studio.pi.activeModel}\n'
      'providers   ${studio.agentProviders.length} ready / '
          '${studio.providers.length} known\n'
      'sessions    ${studio.sessions.all.length}\n'
      'memories    ${studio.memory.all.length}\n'
      'log lines   ${studio.appLog.length}\n'
      'vfs files   ${studio.fs.fileCount}\n'
      'transcript  ${_lines.length} lines',
      PiLineKind.sys,
    );
  }

  ChatSession? _current() {
    final id = _sessionId;
    if (id != null) {
      final s = studio.sessions.byId(id);
      if (s != null) return s;
    }
    final active = studio.sessions.active;
    if (active != null && active.kind == SessionKind.pi) {
      _sessionId = active.id;
      return active;
    }
    return null;
  }

  /// Step the thinking level on by one, wrapping at the top.
  void cycleThinking() {
    final levels = PiThinking.values;
    thinking = levels[(levels.indexOf(thinking) + 1) % levels.length];
    notifyListeners();
  }

  /// Abandon the in-flight turn (^C).
  void cancel() {
    if (!_running) return;
    _running = false;
    _streamIndex = -1;
    _append('^C — turn abandoned', PiLineKind.err);
    notifyListeners();
  }

  @override
  void dispose() {
    _lines.clear();
    _suggestions = const [];
    super.dispose();
  }
}
