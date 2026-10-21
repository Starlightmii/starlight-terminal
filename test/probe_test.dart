import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/palette.dart';
import 'package:flutter_app/ui/widgets/chrome.dart';

void main() {
  testWidgets('TermPanel inside an unbounded Column', (tester) async {
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
    final err = tester.takeException();
    // ignore: avoid_print
    debugPrint('PROBE EXCEPTION -> $err');
  });
}
