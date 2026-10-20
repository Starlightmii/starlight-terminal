import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/agent_runtime.dart';
import 'package:flutter_app/core/agent_scheduler.dart';
import 'package:flutter_app/core/app_log.dart';
import 'package:flutter_app/core/effects.dart';
import 'package:flutter_app/core/memory.dart';
import 'package:flutter_app/core/session_store.dart';

/// Builds a headless session store backed by a real memory store.
SessionStore _store({int maxSessions = 80}) =>
    SessionStore(memories: MemoryStore(), maxSessions: maxSessions);

void main() {
  group('memory store', () {
    test('newest memories come first', () {
      final m = MemoryStore();
      m.add(text: 'first');
      m.add(text: 'second');
      expect(m.all.first.text, 'second');
      expect(m.all.last.text, 'first');
    });

    test('duplicate text is rejected and returns the original', () {
      final m = MemoryStore();
      final a = m.add(text: 'Vega is high');
      final b = m.add(text: '  vega   is HIGH  ');
      expect(b.id, a.id);
      expect(m.length, 1);
    });

    test('empty memories are refused rather than silently stored', () {
      final m = MemoryStore();
      expect(() => m.add(text: '   '), throwsArgumentError);
      expect(m.length, 0);
    });

    test('capacity evicts lowest weight first', () {
      final m = MemoryStore(capacity: 3);
      m.add(text: 'light', weight: 0.2);
      m.add(text: 'heavy', weight: 1.0);
      m.add(text: 'medium', weight: 0.5);
      m.add(text: 'newcomer', weight: 0.6);

      expect(m.length, 3);
      expect(m.all.map((x) => x.text), isNot(contains('light')));
      expect(m.all.map((x) => x.text), contains('heavy'));
    });

    test('session and tag indexes stay consistent after removal', () {
      final m = MemoryStore();
      final a = m.add(text: 'anchored to vega', sessionId: 's1', tags: ['sky']);
      m.add(text: 'unrelated', sessionId: 's2');

      expect(m.forSession('s1').length, 1);
      expect(m.withTag('sky').length, 1);

      m.remove(a.id);
      expect(m.forSession('s1'), isEmpty);
      expect(m.withTag('sky'), isEmpty);
    });

    test('search matches body, author and tags', () {
      final m = MemoryStore();
      m.add(text: 'the moon is waxing', author: 'surveyor', tags: ['lunar']);
      expect(m.search('waxing'), hasLength(1));
      expect(m.search('surveyor'), hasLength(1));
      expect(m.search('lunar'), hasLength(1));
      expect(m.search('nothing here'), isEmpty);
    });

    test('json round-trip preserves the whole store', () {
      final m = MemoryStore();
      m.add(
        text: 'M31 is up',
        source: MemorySource.pi,
        kind: MemoryKind.fact,
        sessionId: 's9',
        author: 'pi',
        tags: ['deep-sky'],
        starId: 'vega',
      );

      final n = MemoryStore();
      n.loadEncoded(m.encode());

      expect(n.length, 1);
      final only = n.all.single;
      expect(only.text, 'M31 is up');
      expect(only.source, MemorySource.pi);
      expect(only.kind, MemoryKind.fact);
      expect(only.starId, 'vega');
      expect(only.tags, ['deep-sky']);
    });

    test('a corrupt line does not destroy the rest of the store', () {
      final m = MemoryStore();
      m.add(text: 'good one');
      m.add(text: 'good two');
      final broken = '${m.encode()}\n{not json at all}';

      final n = MemoryStore();
      n.loadEncoded(broken);
      expect(n.length, 2);
    });

    test('anchored memories are the ones with a star', () {
      final m = MemoryStore();
      m.add(text: 'no anchor here');
      m.add(text: 'on vega', starId: 'vega');
      expect(m.anchored, hasLength(1));
      expect(m.anchored.single.starId, 'vega');
    });
  });

  group('session store', () {
    test('appending a message auto-titles an untitled session', () {
      final s = _store();
      final ses = s.create(kind: SessionKind.pi, title: 'untitled');
      s.appendMessage(
        ses.id,
        SessionMessage(role: 'you', text: 'explain the meridian', at: DateTime.now()),
      );
      expect(ses.title, 'explain the meridian');
    });

    test('remember=true mirrors into the memory store', () {
      final s = _store();
      final ses = s.create(kind: SessionKind.pi);
      s.appendMessage(
        ses.id,
        SessionMessage(role: 'pi', text: 'Sirius culminates at midnight', at: DateTime.now()),
        remember: true,
      );
      expect(s.memories.length, 1);
      expect(s.memories.all.single.source, MemorySource.pi);
      expect(s.memories.all.single.sessionId, ses.id);
    });

    test('errors are never remembered', () {
      final s = _store();
      final ses = s.create(kind: SessionKind.pi);
      s.appendMessage(
        ses.id,
        SessionMessage(
          role: 'sys',
          text: 'bridge unreachable',
          at: DateTime.now(),
          isError: true,
        ),
        remember: true,
      );
      expect(s.memories.length, 0);
      expect(ses.errorCount, 1);
    });

    test('tool messages increment the tool counter', () {
      final s = _store();
      final ses = s.create(kind: SessionKind.pi);
      s.appendMessage(
        ses.id,
        SessionMessage(role: 'tool', text: 'read(/etc/hosts)', at: DateTime.now()),
      );
      expect(ses.toolCalls, 1);
    });

    test('capacity keeps pinned sessions', () {
      final s = _store(maxSessions: 2);
      final a = s.create(kind: SessionKind.pi, title: 'pinned');
      a.pinned = true;
      s.create(kind: SessionKind.bot, title: 'b');
      s.create(kind: SessionKind.bot, title: 'c');

      expect(s.all.length, 2);
      expect(s.all.map((x) => x.title), contains('pinned'));
    });

    test('ensurePi reuses an existing pi session', () {
      final s = _store();
      final a = s.ensurePi();
      final b = s.ensurePi();
      expect(b.id, a.id);
      expect(s.byKind(SessionKind.pi), hasLength(1));
    });

    test('json round-trip preserves transcripts and counters', () {
      final s = _store();
      final ses = s.create(kind: SessionKind.pi, title: 'kept');
      s.appendMessage(
        ses.id,
        SessionMessage(role: 'you', text: 'hello', at: DateTime.now()),
      );
      ses.tokensIn = 12;
      ses.tokensOut = 34;

      final n = _store();
      n.loadEncoded(s.encode());

      final back = n.all.single;
      expect(back.title, 'kept');
      expect(back.messageCount, 1);
      expect(back.messages.single.text, 'hello');
      expect(back.tokensIn, 12);
      expect(back.tokensOut, 34);
    });

    test('stats aggregate across the fleet', () {
      final s = _store();
      final a = s.create(kind: SessionKind.pi);
      final b = s.create(kind: SessionKind.job);
      s.appendMessage(a.id, SessionMessage(role: 'you', text: 'x', at: DateTime.now()));
      s.appendMessage(b.id, SessionMessage(role: 'tool', text: 'y', at: DateTime.now()));

      final st = s.stats;
      expect(st['sessions'], 2);
      expect(st['messages'], 2);
      expect(st['tools'], 1);
    });
  });

  group('agent scheduler', () {
    test('an agent with a task and no history is due immediately', () {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'survey the sky';
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async {},
      );
      expect(s.isDue(agent), isTrue);
      expect(s.armedCount, 1);
    });

    test('an agent without a task is never due', () {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = '';
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async {},
      );
      expect(s.isDue(agent), isFalse);
      expect(s.armedCount, 0);
    });

    test('a disabled agent is not due even when armed', () {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'work';
      agent.enabled = false;
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async {},
      );
      expect(s.isDue(agent), isFalse);
    });

    test('a recently run agent waits for its interval', () {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'work'
        ..everyMinutes = 60
        ..lastAutoRun = DateTime.now();
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async {},
      );
      expect(s.isDue(agent), isFalse);
      expect(s.nextDueIn(agent)!.inMinutes, greaterThan(50));
    });

    test('tick runs due agents and records history', () async {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'survey';
      var ran = 0;
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, task) async {
          ran++;
          expect(task, 'survey');
        },
      );

      await s.tick();
      expect(ran, 1);
      expect(s.history, hasLength(1));
      expect(s.history.first.ok, isTrue);
      expect(agent.autoRuns, 1);
    });

    test('a second tick does not re-run an agent that just ran', () async {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'survey'
        ..everyMinutes = 60;
      var ran = 0;
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async => ran++,
      );

      await s.tick();
      await s.tick();
      expect(ran, 1);
    });

    test('a failing run is recorded rather than crashing the sweep', () async {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'boom';
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async => throw StateError('nope'),
      );

      await s.tick();
      expect(s.history, hasLength(1));
      expect(s.history.first.ok, isFalse);
      expect(s.history.first.note, contains('nope'));
    });

    test('history is capped', () async {
      final agent = AgentPresets.build().first
        ..autoRun = true
        ..task = 'work';
      final s = AgentScheduler(
        agentsProvider: () => [agent],
        runner: (_, __) async {},
        maxHistory: 3,
      );
      for (var i = 0; i < 6; i++) {
        await s.runNow(agent);
      }
      expect(s.history.length, 3);
    });
  });

  group('app log', () {
    test('newest entries come first and severity filters apply', () {
      final l = AppLog();
      l.info('one');
      l.error('two');
      l.debug('three');

      expect(l.all.first.text, 'three');
      l.setFloor(LogLevel.warn);
      expect(l.visible.map((e) => e.text), ['two']);
    });

    test('scope filter narrows by subsystem', () {
      final l = AppLog();
      l.info('bridge up', scope: 'bridge');
      l.info('pi settled', scope: 'pi');

      l.setScopeFilter('pi');
      expect(l.visible, hasLength(1));
      expect(l.visible.single.scope, 'pi');
    });

    test('capacity drops the oldest lines', () {
      final l = AppLog(capacity: 3);
      for (var i = 0; i < 6; i++) {
        l.info('line $i');
      }
      expect(l.length, 3);
      expect(l.all.first.text, 'line 5');
    });

    test('empty writes are ignored', () {
      final l = AppLog();
      l.info('   ');
      expect(l.length, 0);
    });

    test('export is chronological', () {
      final l = AppLog();
      l.info('first');
      l.info('second');
      final lines = l.export().split('\n');
      expect(lines.first, contains('first'));
      expect(lines.last, contains('second'));
    });
  });

  group('deep effect parameters', () {
    test('the new kinds all have labels and descriptions', () {
      for (final k in EffectKind.values) {
        expect(EffectParams.labels[k], isNotNull, reason: '$k has no label');
        expect(EffectParams.descriptions[k], isNotNull);
      }
    });

    test('hue, bloom and warp survive a round-trip', () {
      const p = EffectParams(
        kind: EffectKind.aurora,
        hue: 0.42,
        bloom: 0.8,
        warp: 0.17,
      );
      final back = EffectParams.fromJson(p.toJson());
      expect(back.kind, EffectKind.aurora);
      expect(back.hue, closeTo(0.42, 1e-9));
      expect(back.bloom, closeTo(0.8, 1e-9));
      expect(back.warp, closeTo(0.17, 1e-9));
    });

    test('older saved payloads still load with sane defaults', () {
      final back = EffectParams.fromJson({
        'kind': 'matrix',
        'intensity': 0.5,
      });
      expect(back.hue, 0.0);
      expect(back.bloom, greaterThan(0));
      expect(back.warp, greaterThan(0));
    });
  });
}
