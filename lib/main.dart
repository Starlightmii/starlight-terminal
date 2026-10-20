import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/agent_http.dart';
import 'state/studio_controller.dart';
import 'state/terminal_controller.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Real HTTP for agent -> provider calls. On web this is an XHR and vendor
  // CORS rules apply; on Android it is a plain socket request.
  installHttpBridge();
  runApp(const StarlightApp());
}

class StarlightApp extends StatelessWidget {
  const StarlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TerminalController>(
          create: (_) => TerminalController()..start(),
        ),
        ChangeNotifierProvider<StudioController>(
          create: (context) {
            final terminal = context.read<TerminalController>();
            return StudioController(terminal: terminal)..start();
          },
        ),
      ],
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
      // JetBrains Mono lacks the geometric/technical glyphs used by the
      // chrome (★ ⚙ ◐ ▣ …). On the web there is no OS fallback, so those
      // render as tofu unless we name a bundled face that has them.
      fontFamilyFallback: const <String>['MonoFallback'],
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4FD79A),
        brightness: Brightness.dark,
        surface: bg,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF7CFFC4),
      ),
    );
  }
}
