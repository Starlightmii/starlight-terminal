import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/palette.dart';
import 'package:flutter_app/core/pi_commands.dart';
import 'package:flutter_app/core/pi_core.dart';
import 'package:flutter_app/core/providers.dart';
import 'package:flutter_app/ui/widgets/chrome.dart';

/// Regression tests for the six defects reported after the last build.
void main() {
  group('TermPanel layout', () {
    testWidgets('a header panel shrink-wraps instead of throwing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TermPanel(
                        palette: Palette.phosphor,
                        expand: false,
                        title: 'HEADER',
                        padding: const EdgeInsets.all(8),
                        child: const Text('header'),
                      ),
                      const SizedBox(height: 8),
                      const Expanded(child: Text('body')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // Before the fix this threw
      // "RenderFlex children have non-zero flex but incoming height
      // constraints are unbounded", which made MAP/AGENTS/KEYS unreachable.
      expect(tester.takeException(), isNull);
    });

    testWidgets('an expanding panel still fills its parent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TermPanel(
              palette: Palette.phosphor,
              title: 'BODY',
              child: const Text('body'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('pi catalog', () {
    test('seeds from a configured provider rather than a fixed list', () {
      final pi = PiCore();
      const keyed = Provider(
        id: 'openrouter',
        label: 'OpenRouter',
        kind: ProviderKind.llm,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'anthropic/claude-3.5-sonnet',
        apiKey: 'sk-or-v1-0123456789abcdef0123',
      );
      pi.seedFromProviders([keyed]);

      expect(pi.models, isNotEmpty);
      // The key's own model must be first and must carry its provider.
      expect(pi.models.first.id, 'anthropic/claude-3.5-sonnet');
      expect(pi.models.first.providerId, 'openrouter');
      // And every catalog entry is routable.
      expect(pi.models.every((m) => m.providerId == 'openrouter'), isTrue);
      pi.dispose();
    });

    test('a new key changes the catalog immediately', () {
      final pi = PiCore();
      pi.seedFromProviders(ProviderPresets.all);
      expect(pi.models.any((m) => m.providerId == 'openrouter'), isTrue);

      // Simulate the operator pasting an OpenRouter key and picking a model.
      final keyed = ProviderPresets.all
          .firstWhere((p) => p.id == 'openrouter')
          .copyWith(apiKey: 'sk-or-v1-abcdefabcdefabcdef', model: 'qwen/qwen-2.5-72b-instruct');
      pi.seedFromProviders([keyed]);
      expect(pi.models.any((m) => m.id == 'qwen/qwen-2.5-72b-instruct'), isTrue);
      pi.dispose();
    });

    test('search ranks exact matches first and matches vendors', () {
      final pi = PiCore();
      const or = Provider(
        id: 'openrouter',
        label: 'OpenRouter',
        kind: ProviderKind.llm,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'deepseek/deepseek-r1:free',
        apiKey: 'sk-or-v1-abcdefabcdefabcdef',
      );
      pi.seedFromProviders([or]);

      expect(pi.search('deepseek').first.id, 'deepseek/deepseek-r1:free');
      expect(pi.search('r1'), isNotEmpty);
      expect(pi.search('nothing-matches-this'), isEmpty);
      expect(pi.search('').length, pi.models.length);
      pi.dispose();
    });

    test('resolve accepts an index, a wire id and a provider/id label', () {
      final pi = PiCore();
      const or = Provider(
        id: 'openrouter',
        label: 'OpenRouter',
        kind: ProviderKind.llm,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'meta-llama/llama-3.3-70b-instruct:free',
        apiKey: 'sk-or-v1-abcdefabcdefabcdef',
      );
      pi.seedFromProviders([or]);

      expect(pi.resolve('1')?.id, 'meta-llama/llama-3.3-70b-instruct:free');
      expect(pi.resolve('meta-llama/llama-3.3-70b-instruct:free')?.providerId,
          'openrouter');
      expect(pi.resolve('llama')?.providerId, 'openrouter');
      expect(pi.resolve('99'), isNull);
      pi.dispose();
    });

    test('catalog survives an encode/load round trip', () {
      final pi = PiCore();
      const or = Provider(
        id: 'openrouter',
        label: 'OpenRouter',
        kind: ProviderKind.llm,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'model-a',
        apiKey: 'sk-or-v1-abcdefabcdefabcdef',
      );
      pi.seedFromProviders([or]);
      pi.setModel('model-a');
      final encoded = pi.encodeCatalog();

      final restored = PiCore();
      restored.loadCatalog(encoded);
      restored.seedFromProviders([or]);
      expect(restored.activeModel, 'model-a');
      restored.dispose();
      pi.dispose();
    });

    test('listModels reports a miss instead of an empty string', () async {
      final pi = PiCore();
      const or = Provider(
        id: 'openrouter',
        label: 'OpenRouter',
        kind: ProviderKind.llm,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'only-one',
        apiKey: 'sk-or-v1-abcdefabcdefabcdef',
      );
      pi.seedFromProviders([or]);
      final miss = await pi.listModels(query: 'zzz-nothing');
      expect(miss, contains('no model matching'));
      pi.dispose();
    });
  });

  group('pi command surface', () {
    test('every command the UI advertises is documented', () {
      final names = kPiCommands.map((c) => c.name).toSet();
      for (final expected in [
        '/model',
        '/models',
        '/keys',
        '/net',
        '/commands',
        '/install',
        '/help',
      ]) {
        expect(names.contains(expected), isTrue, reason: 'missing $expected');
      }
    });

    test('command names are unique', () {
      final names = kPiCommands.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
    });
  });
}
