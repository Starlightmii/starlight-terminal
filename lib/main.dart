import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/terminal_controller.dart';
import 'ui/shell.dart';

void main() {
  runApp(const StarlightApp());
}

class StarlightApp extends StatelessWidget {
  const StarlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TerminalController>(
      create: (_) => TerminalController()..start(),
      child: Consumer<TerminalController>(
        builder: (context, term, _) {
          return MaterialApp(
            title: 'Starlight Terminal',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(term.palette.bg),
            home: const StarlightShell(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Color bg) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Mono',
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4FD79A),
        brightness: Brightness.dark,
        surface: bg,
      ),
      splashFactory: InkSparkle.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF7CFFC4),
      ),
    );
  }
}
