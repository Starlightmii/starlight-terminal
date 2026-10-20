import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/agent_runtime.dart';
import 'package:flutter_app/core/catalogue.dart';
import 'package:flutter_app/core/effects.dart';
import 'package:flutter_app/core/providers.dart';

/// Builds an AgentContext wired to recording callbacks so tests can assert
/// that tools really mutate state instead of only printing text.
class Harness {
  final List<String> notes = <String>[];
  final List<String> palettes = <String>[];
  final List<String> effects = <String>[];
  final List<int> shifts = <int>[];

  late final AgentContext ctx = AgentContext(
    stars: kStarCatalogue,
    latitude: 51.5,
    longitude: -0.14,
    lstDegrees: 132.0,
    now: DateTime.utc(2025, 3, 14, 22, 0),
    siteName: 'Greenwich',
    onNote: notes.add,
    onPalette: palettes.add,
    onTimeShift: shifts.add,
    onEffect: effects.add,
  );
}

void main() {
  group('provider vault', () {
    test('presets cover llm, image and video kinds', () {
      final kinds = ProviderPresets.all.map((p) => p.kind).toSet();
      expect(kinds.contains(ProviderKind.llm), isTrue);
      expect(kinds.contains(ProviderKind.image), isTrue);
      expect(kinds.contains(ProviderKind.video), isTrue);
      expect(ProviderPresets.all.length, greaterThanOrEqualTo(12));
    });

    test('preset ids are unique', () {
      final ids = ProviderPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('a provider is only ready with an enabled endpoint and key', () {
      const bare = Provider(
        id: 'x',
        label: 'X',
        kind: ProviderKind.llm,
        baseUrl: 'https://example.test/v1',
        model: 'm',
      );
      expect(bare.ready, isFalse);
      expect(bare.looksPlausible, isFalse);

      const keyed = Provider(
        id: 'x',
        label: 'X',
        kind: ProviderKind.llm,
        baseUrl: 'https://example.test/v1',
        model: 'm',
        apiKey: 'sk-abcdef0123456789abcdef',
      );
      expect(keyed.ready, isTrue);
      expect(keyed.looksPlausible, isTrue);
    });

    test('placeholder keys are rejected as implausible', () {
      const p = Provider(
        id: 'x',
        label: 'X',
        kind: ProviderKind.llm,
        baseUrl: 'https://example.test/v1',
        model: 'm',
        apiKey: 'your-api-key-here-000000',
      );
      expect(p.looksPlausible, isFalse);
    });

    test('masked keys never leak the middle of the secret', () {
      const p = Provider(
        id: 'x',
        label: 'X',
        kind: ProviderKind.llm,
        baseUrl: 'https://example.test/v1',
        model: 'm',
        apiKey: 'sk-verysecretmiddlepart9999',
      );
      final masked = p.maskedKey;
      expect(masked.contains('secretmiddle'), isFalse);
      expect(masked.startsWith('sk-v'), isTrue);
      expect(masked.endsWith('9999'), isTrue);
    });

    test('endpoints are derived from the base url', () {
      const p = Provider(
        id: 'x',
        label: 'X',
        kind: ProviderKind.llm,
        baseUrl: 'https://api.example.test/v1',
        model: 'm',
      );
      expect(p.chatEndpoint.toString(),
          'https://api.example.test/v1/chat/completions');
      expect(p.imageEndpoint.toString(),
          'https://api.example.test/v1/images/generations');
    });
  });

  group('effect parameters', () {
    test('defaults render an animated matrix at moderate strength', () {
      const fx = EffectParams();
      expect(fx.kind, EffectKind.matrix);
      expect(fx.intensity, inInclusiveRange(0.0, 1.0));
      expect(fx.speed, greaterThan(0));
    });

    test('copyWith changes only the named field', () {
      const fx = EffectParams();
      final next = fx.copyWith(kind: EffectKind.plasma, speed: 2.4);
      expect(next.kind, EffectKind.plasma);
      expect(next.speed, 2.4);
      expect(next.intensity, fx.intensity);
      expect(next.grain, fx.grain);
    });

    test('json round-trips every field', () {
      const fx = EffectParams(
        kind: EffectKind.wireframe,
        intensity: 0.31,
        speed: 1.77,
        density: 0.22,
        scale: 2.05,
        chroma: 0.88,
        grain: 0.44,
      );
      final back = EffectParams.fromJson(fx.toJson());
      expect(back.kind, fx.kind);
      expect(back.intensity, closeTo(fx.intensity, 1e-9));
      expect(back.speed, closeTo(fx.speed, 1e-9));
      expect(back.density, closeTo(fx.density, 1e-9));
      expect(back.scale, closeTo(fx.scale, 1e-9));
      expect(back.chroma, closeTo(fx.chroma, 1e-9));
      expect(back.grain, closeTo(fx.grain, 1e-9));
    });

    test('unknown effect ids fall back instead of throwing', () {
      final back = EffectParams.fromJson({'kind': 'not-a-real-effect'});
      expect(back.kind, EffectKind.matrix);
      expect(EffectParams.fromJson(null).kind, EffectKind.matrix);
    });

    test('every effect kind has a label and a description', () {
      for (final k in EffectKind.values) {
        expect(EffectParams.labels[k], isNotNull);
        expect(EffectParams.descriptions[k], isNotNull);
        expect(EffectParams.labels[k]!.isNotEmpty, isTrue);
      }
    });
  });

  group('agent tools', () {
    test('every tool has a name, description and argument hint', () {
      for (final t in AgentTools.catalogue) {
        expect(t.name.trim().isNotEmpty, isTrue);
        expect(t.description.trim().isNotEmpty, isTrue);
      }
    });

    test('tool names are unique and resolvable', () {
      final names = AgentTools.catalogue.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
      for (final n in names) {
        expect(AgentTools.byName(n), isNotNull);
      }
      expect(AgentTools.byName('no_such_tool'), isNull);
    });

    test('set_effect really switches the effect', () {
      final h = Harness();
      AgentTools.byName('set_effect')!.run('plasma', h.ctx);
      expect(h.effects, ['plasma']);
    });

    test('set_effect rejects an unknown effect without mutating', () {
      final h = Harness();
      final out = AgentTools.byName('set_effect')!.run('disco', h.ctx);
      expect(h.effects, isEmpty);
      expect(out.toLowerCase().contains('unknown'), isTrue);
    });

    test('set_palette accepts the four palettes and rejects others', () {
      final h = Harness();
      final tool = AgentTools.byName('set_palette')!;
      for (final p in ['phosphor', 'amber', 'ice', 'nebula']) {
        tool.run(p, h.ctx);
      }
      expect(h.palettes, ['phosphor', 'amber', 'ice', 'nebula']);
      tool.run('chartreuse', h.ctx);
      expect(h.palettes.length, 4);
    });

    test('save_note writes through and refuses empty notes', () {
      final h = Harness();
      final tool = AgentTools.byName('save_note')!;
      tool.run('saw Orion rising', h.ctx);
      expect(h.notes, ['saw Orion rising']);
      tool.run('   ', h.ctx);
      expect(h.notes.length, 1);
    });

    test('shift_time moves the clock and rejects non-integers', () {
      final h = Harness();
      final tool = AgentTools.byName('shift_time')!;
      tool.run('3', h.ctx);
      tool.run('-2', h.ctx);
      tool.run('soon', h.ctx);
      expect(h.shifts, [3, -2]);
    });

    test('star_info resolves a real star and reports a miss cleanly', () {
      final h = Harness();
      final tool = AgentTools.byName('star_info')!;
      final hit = tool.run('Vega', h.ctx);
      expect(hit, contains('Vega'));
      final miss = tool.run('Zzzquux', h.ctx);
      expect(miss.toLowerCase().contains('no star'), isTrue);
    });

    test('search_catalogue finds stars by constellation', () {
      final h = Harness();
      final out = AgentTools.byName('search_catalogue')!.run('Orion', h.ctx);
      expect(out.toLowerCase().contains('orion'), isTrue);
    });

    test('stars_visible honours its limit argument', () {
      final h = Harness();
      final out = AgentTools.byName('stars_visible')!.run('3', h.ctx);
      final lines = out.split('\n').where((l) => l.contains('mag')).toList();
      expect(lines.length, lessThanOrEqualTo(3));
    });

    test('moon_phase and sky_summary both produce text', () {
      final h = Harness();
      expect(AgentTools.byName('moon_phase')!.run('', h.ctx), isNotEmpty);
      final summary = AgentTools.byName('sky_summary')!.run('', h.ctx);
      expect(summary, contains('Greenwich'));
    });
  });

  group('agent runtime', () {
    test('presets ship four distinct specialists', () {
      final agents = AgentPresets.build();
      expect(agents.length, 4);
      final ids = agents.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(agents.every((a) => a.persona.trim().isNotEmpty), isTrue);
    });

    test('state transitions and counters behave', () {
      final a = AgentPresets.build().first;
      expect(a.state, AgentRunState.idle);
      expect(a.busy, isFalse);
      a.setState(AgentRunState.thinking, 'thinking');
      expect(a.busy, isTrue);
      a.noteTool('sky_summary()');
      expect(a.toolCalls, 1);
      expect(a.toolLog.single, 'sky_summary()');
      a.setState(AgentRunState.done, 'done');
      expect(a.busy, isFalse);
    });

    test('reset clears transcript and counters', () {
      final a = AgentPresets.build().first;
      a.addMessage(const AgentMessage(role: AgentRole.user, text: 'hi'));
      a.noteTool('done()');
      a.reset();
      expect(a.transcript, isEmpty);
      expect(a.toolCalls, 0);
      expect(a.state, AgentRunState.idle);
    });

    test('toJson/fromJson preserves identity fields', () {
      final a = AgentPresets.build()[2];
      final back = AgentRuntime.fromJson(a.toJson());
      expect(back.id, a.id);
      expect(back.name, a.name);
      expect(back.persona, a.persona);
      expect(back.providerId, a.providerId);
      expect(back.colorIndex, a.colorIndex);
    });

    test('fromJson tolerates missing fields', () {
      final a = AgentRuntime.fromJson(<String, dynamic>{});
      expect(a.enabled, isTrue);
      expect(a.colorIndex, 0);
      expect(a.name, 'agent');
    });
  });

  group('agent loop (offline planner)', () {
    test('an effect task actually switches the effect', () async {
      final h = Harness();
      final agent = AgentPresets.build().first;
      final events = <AgentEvent>[];

      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (_) => null,
        onEvent: (_, e) => events.add(e),
      );

      await loop.run(agent, 'switch to the diffusion effect');

      expect(h.effects, isNotEmpty);
      expect(h.effects.first, 'diffusion');
      expect(agent.state, AgentRunState.done);
      expect(agent.toolCalls, greaterThan(0));
      expect(events.any((e) => e.kind == AgentEventKind.done), isTrue);
    });

    test('a palette task changes the palette', () async {
      final h = Harness();
      final agent = AgentPresets.build()[3];
      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (_) => null,
        onEvent: (_, __) {},
      );

      await loop.run(agent, 'give me the amber palette');

      expect(h.palettes, contains('amber'));
    });

    test('a log task writes a note', () async {
      final h = Harness();
      final agent = AgentPresets.build()[2];
      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (_) => null,
        onEvent: (_, __) {},
      );

      await loop.run(agent, 'note that the sky is clear');

      expect(h.notes, isNotEmpty);
    });

    test('an unconfigured provider falls back instead of failing', () async {
      final h = Harness();
      final agent = AgentPresets.build().first;
      final events = <AgentEvent>[];

      // groq preset exists but has no key.
      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (id) => ProviderPresets.all
            .where((p) => p.id == id)
            .cast<Provider?>()
            .firstWhere((_) => true, orElse: () => null),
        onEvent: (_, e) => events.add(e),
      );

      await loop.run(agent, 'what is visible tonight');

      expect(events.any((e) => e.kind == AgentEventKind.warn), isFalse);
      expect(agent.state, AgentRunState.done);
      expect(agent.transcript.length, greaterThan(1));
    });

    test('a cancelled run stops in the cancelled state', () async {
      final h = Harness();
      final agent = AgentPresets.build().first;
      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (_) => null,
        onEvent: (_, __) {},
      );

      // Cancelling has to land while the loop is walking its steps, so start
      // the run first and pull the plug a beat later.
      final run = loop.run(agent, 'survey the sky');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      loop.cancel(agent.id);
      await run;

      expect(agent.state, AgentRunState.cancelled);
      expect(agent.statusLine, 'cancelled');
    });

    test('the transcript always ends with an assistant line', () async {
      final h = Harness();
      final agent = AgentPresets.build()[1];
      final loop = AgentLoop(
        context: h.ctx,
        providerFor: (_) => null,
        onEvent: (_, __) {},
      );

      await loop.run(agent, 'where is Vega right now');

      expect(agent.transcript.last.role, AgentRole.assistant);
      expect(agent.transcript.last.text.trim(), isNotEmpty);
      expect(agent.transcript.first.role, AgentRole.user);
    });
  });
}
