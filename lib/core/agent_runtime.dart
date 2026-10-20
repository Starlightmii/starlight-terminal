import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'catalogue.dart';
import 'console_engine.dart';
import 'providers.dart';

/// Status of one agent turn.
enum AgentRunState { idle, thinking, toolCall, done, error, cancelled }

/// A message in an agent's conversation transcript.
enum AgentRole { system, user, assistant, tool }

@immutable
class AgentMessage {
  const AgentMessage({
    required this.role,
    required this.text,
    this.toolName,
    this.createdAt,
  });

  final AgentRole role;
  final String text;
  final String? toolName;
  final DateTime? createdAt;

  String get prefix => switch (role) {
        AgentRole.system => 'sys',
        AgentRole.user => 'you',
        AgentRole.assistant => 'agt',
        AgentRole.tool => 'tool',
      };
}

/// A tool an agent can call. Mirrors Pi's design: a name, a description the
/// model reads, a JSON-ish schema for arguments, and a synchronous executor
/// that returns text (which goes back into the model's context).
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.args,
    required this.run,
  });

  final String name;
  final String description;

  /// Human-readable argument list, e.g. `<ra> <dec>` or `<query>`.
  final String args;

  /// Executor receives the raw argument string the model produced.
  final String Function(String args, AgentContext ctx) run;
}

/// Everything a tool needs to touch: the catalogue, the log, the site.
class AgentContext {
  AgentContext({
    required this.stars,
    required this.latitude,
    required this.longitude,
    required this.lstDegrees,
    required this.now,
    required this.siteName,
    required this.onNote,
    required this.onPalette,
    required this.onTimeShift,
    required this.onEffect,
  });

  final List<Star> stars;
  final double latitude;
  final double longitude;
  final double lstDegrees;
  final DateTime now;
  final String siteName;

  final void Function(String text) onNote;
  final void Function(String paletteName) onPalette;
  final void Function(int hours) onTimeShift;
  final void Function(String effectId) onEffect;

  Star? findStar(String needle) {
    final q = needle.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final s in stars) {
      if (s.name.toLowerCase() == q) return s;
    }
    for (final s in stars) {
      if (s.name.toLowerCase().startsWith(q)) return s;
    }
    for (final s in stars) {
      if (s.name.toLowerCase().contains(q) ||
          s.constellation.toLowerCase().contains(q) ||
          s.bayer.toLowerCase().contains(q)) {
        return s;
      }
    }
    return null;
  }

  List<Star> visible() {
    final v = stars.where((s) => s.altitude > 0).toList()
      ..sort((a, b) => a.magnitude.compareTo(b.magnitude));
    return v;
  }
}

/// The built-in tool set — every one of these actually mutates or reads real
/// terminal state, the same way Pi's tools touch real files.
class AgentTools {
  static final List<AgentTool> catalogue = <AgentTool>[
    AgentTool(
      name: 'stars_visible',
      description:
          'List catalogued stars currently above the horizon, brightest first.',
      args: '[limit]',
      run: (args, ctx) {
        final limit = int.tryParse(args.trim()) ?? 8;
        final vis = ctx.visible();
        if (vis.isEmpty) return 'No catalogued stars are above the horizon.';
        final b = StringBuffer('${vis.length} stars above horizon. Top $limit:\n');
        for (final s in vis.take(limit)) {
          b.writeln('${s.name} (${s.constellation}) mag ${fmtMag(s.magnitude)} '
              'alt ${s.altitude.toStringAsFixed(1)}° '
              'az ${s.azimuth.toStringAsFixed(0)}°');
        }
        return b.toString();
      },
    ),
    AgentTool(
      name: 'star_info',
      description: 'Full data sheet for one star by name.',
      args: '<name>',
      run: (args, ctx) {
        final s = ctx.findStar(args);
        if (s == null) return 'No star matching "${args.trim()}" in catalogue.';
        return '${s.name} — ${s.bayer}, ${s.constellation}\n'
            'RA ${fmtRa(s.raHours)} Dec ${fmtDec(s.decDegrees)}\n'
            'magnitude ${fmtMag(s.magnitude)}, spectral ${s.spectral}, '
            'distance ${fmtDistance(s.distanceLy)}\n'
            'altitude ${s.altitude.toStringAsFixed(1)}° '
            'azimuth ${s.azimuth.toStringAsFixed(0)}° '
            '(${compassPoint(s.azimuth)})\n'
            '${s.note}';
      },
    ),
    AgentTool(
      name: 'sky_summary',
      description: 'One-paragraph summary of the current sky and moon.',
      args: '',
      run: (args, ctx) {
        final vis = ctx.visible();
        final top = vis.isEmpty ? 'nothing' : vis.take(3).map((s) => s.name).join(', ');
        final phase = moonPhaseName(moonPhase(ctx.now.toUtc()));
        final lst = (ctx.lstDegrees / 15).toStringAsFixed(2);
        return 'Site ${ctx.siteName} (${ctx.latitude.toStringAsFixed(2)}, '
            '${ctx.longitude.toStringAsFixed(2)}). LST ${lst}h. '
            '${vis.length} catalogue objects above horizon; brightest: $top. '
            'Moon is $phase.';
      },
    ),
    AgentTool(
      name: 'moon_phase',
      description: 'Current lunar phase and illumination.',
      args: '',
      run: (args, ctx) {
        final p = moonPhase(ctx.now.toUtc());
        final illum = (1 - math.cos(2 * math.pi * p)) / 2;
        return '$moonGlyph(p) $moonPhaseName(p), '
            '${(illum * 100).toStringAsFixed(0)}% illuminated, '
            'cycle ${(p * 100).toStringAsFixed(0)}%.';
      },
    ),
    AgentTool(
      name: 'save_note',
      description: 'Append a line to the observing log.',
      args: '<text>',
      run: (args, ctx) {
        final text = args.trim();
        if (text.isEmpty) return 'Refused: empty note.';
        ctx.onNote(text);
        return 'Saved to observing log: "$text"';
      },
    ),
    AgentTool(
      name: 'set_palette',
      description: 'Change the terminal phosphor palette: '
          'phosphor, amber, ice, or nebula.',
      args: '<name>',
      run: (args, ctx) {
        final name = args.trim().toLowerCase();
        const ok = {'phosphor', 'amber', 'ice', 'nebula'};
        if (!ok.contains(name)) {
          return 'Unknown palette "$name". Valid: ${ok.join(', ')}.';
        }
        ctx.onPalette(name);
        return 'Palette switched to $name.';
      },
    ),
    AgentTool(
      name: 'set_effect',
      description: 'Switch the background effect: '
          'matrix, diffusion, layers, plasma, wireframe, or none.',
      args: '<effect>',
      run: (args, ctx) {
        final id = args.trim().toLowerCase();
        const ok = {
          'matrix',
          'diffusion',
          'layers',
          'plasma',
          'wireframe',
          'none',
        };
        if (!ok.contains(id)) {
          return 'Unknown effect "$id". Valid: ${ok.join(', ')}.';
        }
        ctx.onEffect(id);
        return 'Background effect set to $id.';
      },
    ),
    AgentTool(
      name: 'shift_time',
      description: 'Move the observing clock forward or back by N hours, '
          'to see how the sky changes.',
      args: '<hours>',
      run: (args, ctx) {
        final n = int.tryParse(args.trim());
        if (n == null) return 'Need an integer number of hours.';
        ctx.onTimeShift(n);
        return 'Observing clock shifted ${n >= 0 ? '+' : ''}$n h.';
      },
    ),
    AgentTool(
      name: 'search_catalogue',
      description: 'Search the star catalogue by name, constellation or Bayer.',
      args: '<query>',
      run: (args, ctx) {
        final q = args.trim().toLowerCase();
        if (q.isEmpty) return 'Empty query.';
        final hits = ctx.stars
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.constellation.toLowerCase().contains(q) ||
                s.bayer.toLowerCase().contains(q))
            .take(10)
            .toList();
        if (hits.isEmpty) return 'No matches for "$q".';
        return hits
            .map((s) => '${s.name} (${s.constellation}) mag ${fmtMag(s.magnitude)} '
                'alt ${s.altitude.toStringAsFixed(0)}°')
            .join('\n');
      },
    ),
    AgentTool(
      name: 'done',
      description: 'Signal that the task is complete. Call this last.',
      args: '[summary]',
      run: (args, ctx) => 'Task complete. ${args.trim()}',
    ),
  ];

  static AgentTool? byName(String name) {
    for (final t in catalogue) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// One configured agent instance — a persona plus its own transcript.
class AgentRuntime extends ChangeNotifier {
  AgentRuntime({
    required this.id,
    required this.name,
    required this.persona,
    required this.providerId,
    this.enabled = true,
    this.colorIndex = 0,
  });

  final String id;
  final String name;
  final String persona;
  final String providerId;
  bool enabled;
  final int colorIndex;

  final List<AgentMessage> transcript = <AgentMessage>[];
  AgentRunState state = AgentRunState.idle;
  String statusLine = 'idle';
  int tokensIn = 0;
  int tokensOut = 0;
  int toolCalls = 0;
  DateTime? lastActive;

  /// Rolling log of tool invocations, newest last.
  final List<String> toolLog = <String>[];

  void reset() {
    transcript.clear();
    state = AgentRunState.idle;
    statusLine = 'idle';
    tokensIn = 0;
    tokensOut = 0;
    toolCalls = 0;
    toolLog.clear();
    notifyListeners();
  }

  void addMessage(AgentMessage m) {
    transcript.add(m);
    lastActive = DateTime.now();
    notifyListeners();
  }

  void setState(AgentRunState s, String status) {
    state = s;
    statusLine = status;
    lastActive = DateTime.now();
    notifyListeners();
  }

  void noteTool(String call) {
    toolCalls++;
    toolLog.add(call);
    if (toolLog.length > 40) toolLog.removeAt(0);
    notifyListeners();
  }

  bool get busy =>
      state == AgentRunState.thinking || state == AgentRunState.toolCall;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'persona': persona,
        'providerId': providerId,
        'enabled': enabled,
        'colorIndex': colorIndex,
      };

  static AgentRuntime fromJson(Map<String, dynamic> j) => AgentRuntime(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'agent').toString(),
        persona: (j['persona'] ?? '').toString(),
        providerId: (j['providerId'] ?? '').toString(),
        enabled: j['enabled'] as bool? ?? true,
        colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
      );
}

/// The agent loop. Mirrors Pi's architecture: build context, ask the model,
/// stream events, execute tools, feed results back, repeat until `done`.
///
/// When a provider has a real key the loop calls it. When no key is
/// configured (or the browser blocks the request) it runs in **simulation**
/// mode: a deterministic planner drives the same tool set against real
/// terminal state, so every agent action still genuinely works.
class AgentLoop {
  AgentLoop({
    required this.context,
    required this.providerFor,
    required this.onEvent,
  });

  final AgentContext context;

  /// Resolve the provider an agent should use.
  final Provider? Function(String providerId) providerFor;

  /// Stream of human-readable events for the transcript pane.
  final void Function(AgentRuntime agent, AgentEvent event) onEvent;

  final Map<String, bool> _cancelled = <String, bool>{};

  void cancel(String agentId) => _cancelled[agentId] = true;

  bool _isCancelled(String id) => _cancelled[id] ?? false;

  /// Run one task on one agent. Completes when the agent stops.
  Future<void> run(
    AgentRuntime agent,
    String task, {
    int maxTurns = 6,
  }) async {
    _cancelled[agent.id] = false;
    agent.addMessage(AgentMessage(
      role: AgentRole.user,
      text: task,
      createdAt: DateTime.now(),
    ));

    final provider = providerFor(agent.providerId);
    final live = provider != null &&
        provider.ready &&
        provider.looksPlausible &&
        provider.kind == ProviderKind.llm;

    if (live) {
      try {
        await _runLive(agent, provider, task, maxTurns);
        return;
      } catch (e) {
        agent.addMessage(AgentMessage(
          role: AgentRole.system,
          text: 'Live call failed (${_shortError(e)}). '
              'Falling back to offline planner.',
        ));
        onEvent(agent, AgentEvent(
          kind: AgentEventKind.warn,
          text: 'live call failed → offline planner',
        ));
      }
    }

    await _runOffline(agent, provider, task, maxTurns);
  }

  String _shortError(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  // ── Live path ───────────────────────────────────────────────────────────

  Future<void> _runLive(
    AgentRuntime agent,
    Provider provider,
    String task,
    int maxTurns,
  ) async {
    agent.setState(AgentRunState.thinking, 'calling ${provider.label}');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(agent)},
      // Replay the recent transcript so multi-turn work stays coherent.
      for (final m in agent.transcript.length > 12
          ? agent.transcript.sublist(agent.transcript.length - 12)
          : agent.transcript)
        if (m.role == AgentRole.user || m.role == AgentRole.assistant)
          {'role': m.role.name, 'content': m.text},
    ];

    for (var turn = 0; turn < maxTurns; turn++) {
      if (_isCancelled(agent.id)) {
        agent.setState(AgentRunState.cancelled, 'cancelled');
        return;
      }

      final resp = await _postChat(provider, messages, tools: true);
      agent.tokensIn += resp.promptTokens;
      agent.tokensOut += resp.completionTokens;

      final content = resp.content.trim();
      if (content.isNotEmpty) {
        agent.addMessage(AgentMessage(
          role: AgentRole.assistant,
          text: content,
          createdAt: DateTime.now(),
        ));
        onEvent(agent, AgentEvent(kind: AgentEventKind.message, text: content));
      }

      messages.add({'role': 'assistant', 'content': content});

      if (resp.toolCall == null) {
        agent.setState(AgentRunState.done, 'done');
        onEvent(agent, const AgentEvent(
          kind: AgentEventKind.done,
          text: 'turn complete',
        ));
        return;
      }

      final call = resp.toolCall!;
      agent.setState(AgentRunState.toolCall, '${call.name}(${call.args})');
      onEvent(agent, AgentEvent(
        kind: AgentEventKind.tool,
        text: '${call.name} ${call.args}',
      ));

      final tool = AgentTools.byName(call.name);
      final result = tool == null
          ? 'Unknown tool "${call.name}".'
          : tool.run(call.args, context);

      agent.noteTool('${call.name}(${call.args})');
      agent.addMessage(AgentMessage(
        role: AgentRole.tool,
        text: result,
        toolName: call.name,
        createdAt: DateTime.now(),
      ));
      onEvent(agent, AgentEvent(
        kind: AgentEventKind.toolResult,
        text: result,
      ));

      messages.add({
        'role': 'user',
        'content': 'TOOL RESULT ${call.name}: $result',
      });

      if (call.name == 'done') {
        agent.setState(AgentRunState.done, 'done');
        return;
      }
    }

    agent.setState(AgentRunState.done, 'turn limit reached');
  }

  String _systemPrompt(AgentRuntime agent) {
    final t = AgentTools.catalogue
        .map((t) => '- ${t.name} ${t.args}: ${t.description}')
        .join('\n');
    return 'You are ${agent.name}, an agent inside Starlight Terminal, a TUI '
        'sky console. ${agent.persona}\n\n'
        'Reply with either prose, or exactly one line of the form:\n'
        'TOOL <name> <args>\n'
        'Available tools:\n$t\n'
        'Always finish by calling done. Be terse — this is a terminal.';
  }

  Future<_ChatResponse> _postChat(
    Provider provider,
    List<Map<String, dynamic>> messages, {
    required bool tools,
  }) async {
    final body = jsonEncode({
      'model': provider.model,
      'messages': messages,
      'temperature': provider.temperature,
      'max_tokens': provider.maxTokens,
    });

    final packed = await httpPostJson(
      uri: provider.chatEndpoint,
      headers: {
        'Authorization': 'Bearer ${provider.apiKey}',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    final decoded = jsonDecode(packed) as Map<String, dynamic>;
    final choice = (decoded['choices'] as List?)?.first as Map?;
    final content =
        ((choice?['message'] as Map?)?['content'] ?? '').toString();

    final usage = decoded['usage'] as Map?;
    // Parse our one-line tool protocol out of the prose.
    final toolCall = _parseToolCall(content);

    return _ChatResponse(
      content: content,
      toolCall: toolCall,
      promptTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  _ToolCall? _parseToolCall(String content) {
    final m = RegExp(r'TOOL\s+([a-z_]+)\s*(.*)', caseSensitive: false)
        .firstMatch(content);
    if (m == null) return null;
    return _ToolCall(m.group(1)!, (m.group(2) ?? '').trim());
  }

  // ── Offline planner ─────────────────────────────────────────────────────

  /// A deterministic planner that executes real tools against real state.
  /// This is not a fake "thinking" animation — each step mutates the app.
  Future<void> _runOffline(
    AgentRuntime agent,
    Provider? provider,
    String task,
    int maxTurns,
  ) async {
    final q = task.toLowerCase();
    agent.setState(AgentRunState.thinking, 'planning (offline)');
    await _pause(260);
    onEvent(agent, AgentEvent(
      kind: AgentEventKind.thinking,
      text: provider == null
          ? 'no provider bound — planning locally'
          : '${provider.label} unreachable — planning locally',
    ));

    final steps = <_ToolCall>[];

    // Intent matching over the task text.
    if (RegExp(r'\b(matrix|effect|shader|visual|plasma|diffusion|layer)\b')
        .hasMatch(q)) {
      final want = [
        'matrix',
        'diffusion',
        'layers',
        'plasma',
        'wireframe',
      ].firstWhere(q.contains, orElse: () => 'matrix');
      steps.add(_ToolCall('set_effect', want));
    }
    if (RegExp(r'\b(palette|theme|colour|color|phosphor)\b').hasMatch(q)) {
      final want = ['amber', 'ice', 'nebula', 'phosphor']
          .firstWhere(q.contains, orElse: () => 'amber');
      steps.add(_ToolCall('set_palette', want));
    }
    final starMatch = _extractStarName(task);
    if (starMatch != null) {
      steps.add(_ToolCall('star_info', starMatch));
    }
    if (RegExp(r'\b(what|which|see|visible|look|up|sky)\b').hasMatch(q) ||
        steps.isEmpty) {
      steps.add(const _ToolCall('sky_summary', ''));
      steps.add(const _ToolCall('stars_visible', '6'));
    }
    if (q.contains('moon')) {
      steps.add(const _ToolCall('moon_phase', ''));
    }
    final hourMatch = RegExp(r'([+-]?\d{1,2})\s*(h|hour|hr)').firstMatch(q);
    if (hourMatch != null) {
      steps.add(_ToolCall('shift_time', hourMatch.group(1)!));
    }
    if (RegExp(r'\b(note|log|record|remember)\b').hasMatch(q)) {
      steps.add(_ToolCall('save_note', 'agent ${agent.name}: $task'));
    }
    steps.add(const _ToolCall('done', 'finished'));

    for (final step in steps.take(maxTurns)) {
      if (_isCancelled(agent.id)) {
        agent.setState(AgentRunState.cancelled, 'cancelled');
        onEvent(agent, const AgentEvent(
          kind: AgentEventKind.warn,
          text: 'cancelled by user',
        ));
        return;
      }
      agent.setState(AgentRunState.toolCall, '${step.name}(${step.args})');
      onEvent(agent, AgentEvent(
        kind: AgentEventKind.tool,
        text: '${step.name} ${step.args}'.trim(),
      ));
      await _pause(180);

      final tool = AgentTools.byName(step.name);
      final result = tool == null
          ? 'Unknown tool "${step.name}".'
          : tool.run(step.args, context);

      agent.noteTool('${step.name}(${step.args})'.trim());
      agent.addMessage(AgentMessage(
        role: AgentRole.tool,
        text: result,
        toolName: step.name,
        createdAt: DateTime.now(),
      ));
      onEvent(agent, AgentEvent(
        kind: AgentEventKind.toolResult,
        text: result,
      ));
      await _pause(140);
    }

    // A closing line in the agent's own voice.
    final closing = _closingLine(agent, task);
    agent.addMessage(AgentMessage(
      role: AgentRole.assistant,
      text: closing,
      createdAt: DateTime.now(),
    ));
    onEvent(agent, AgentEvent(kind: AgentEventKind.message, text: closing));
    agent.setState(AgentRunState.done, 'done');
    onEvent(agent, const AgentEvent(
      kind: AgentEventKind.done,
      text: 'turn complete',
    ));
  }

  String _closingLine(AgentRuntime agent, String task) {
    switch (agent.id) {
      case 'surveyor':
        return 'Survey complete. ${context.visible().length} objects above the '
            'horizon at ${context.siteName}.';
      case 'navigator':
        return 'Coordinates resolved. Sidereal time '
            '${(context.lstDegrees / 15).toStringAsFixed(2)}h.';
      case 'scribe':
        return 'Logged. The observing record is updated.';
      case 'curator':
        return 'Visual pass done. Tell me if you want a different palette.';
      default:
        return 'Done.';
    }
  }

  String? _extractStarName(String task) {
    for (final s in context.stars) {
      if (task.toLowerCase().contains(s.name.toLowerCase())) return s.name;
    }
    return null;
  }

  Future<void> _pause(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}

class _ToolCall {
  const _ToolCall(this.name, this.args);
  final String name;
  final String args;
}

class _ChatResponse {
  const _ChatResponse({
    required this.content,
    required this.toolCall,
    required this.promptTokens,
    required this.completionTokens,
  });

  final String content;
  final _ToolCall? toolCall;
  final int promptTokens;
  final int completionTokens;
}

enum AgentEventKind { thinking, tool, toolResult, message, done, warn, info }

@immutable
class AgentEvent {
  const AgentEvent({required this.kind, required this.text});
  final AgentEventKind kind;
  final String text;
}

/// Default agent roster — four specialists so multi-agent runs are meaningful.
abstract final class AgentPresets {
  static List<AgentRuntime> build() => <AgentRuntime>[
        AgentRuntime(
          id: 'surveyor',
          name: 'SURVEYOR',
          persona:
              'You survey the sky. You report what is above the horizon and '
              'summarise conditions concisely.',
          providerId: 'groq',
          colorIndex: 0,
        ),
        AgentRuntime(
          id: 'navigator',
          name: 'NAVIGATOR',
          persona:
              'You handle coordinates and time. You resolve star positions and '
              'explain where to look.',
          providerId: 'openai',
          colorIndex: 1,
        ),
        AgentRuntime(
          id: 'scribe',
          name: 'SCRIBE',
          persona:
              'You keep the observing log. You record notes faithfully and '
              'never invent observations.',
          providerId: 'groq',
          colorIndex: 2,
        ),
        AgentRuntime(
          id: 'curator',
          name: 'CURATOR',
          persona:
              'You tune the terminal look: palettes and background effects. '
              'You favour legibility.',
          providerId: 'openai',
          colorIndex: 3,
        ),
      ];
}

// ══════════════════════════════════════════════════════════════════════════
// HTTP bridge
// ══════════════════════════════════════════════════════════════════════════

/// Set by [AgentHttpBridge] at startup. Kept as a thin indirection so the
/// runtime stays testable without a live socket.
typedef HttpPostJson = Future<String> Function({
  required Uri uri,
  required Map<String, String> headers,
  required String body,
});

/// Default implementation. Uses `dart:io` on mobile and `package:http` on web;
/// declared in `agent_http.dart` and injected from `main.dart`.
HttpPostJson? httpPostJsonImpl;

Future<String> httpPostJson({
  required Uri uri,
  required Map<String, String> headers,
  required String body,
}) {
  final impl = httpPostJsonImpl;
  if (impl == null) {
    throw StateError('HTTP bridge not installed');
  }
  return impl(uri: uri, headers: headers, body: body);
}
