import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

const _localizations = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class HubiTimeApp extends StatelessWidget {
  const HubiTimeApp({super.key, required this.session, required this.theme});

  final SessionController session;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AppServices(
      session: session,
      theme: theme,
      child: ListenableBuilder(
        listenable: theme,
        builder: (context, _) => MaterialApp(
          title: 'Hubi Time',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: theme.mode,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: _localizations,
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final session = AppServices.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => AnimatedSwitcher(
        duration: motion(context, 250),
        child: session.isSignedIn
            ? HomeShell(key: ValueKey(session.user!.id))
            : const LoginScreen(key: ValueKey('login')),
      ),
    );
  }
}

/// Mostrado quando o app foi compilado sem as variáveis do Supabase.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'App sem configuração.\n\nCompile com SUPABASE_URL e SUPABASE_ANON_KEY '
                '(veja o README: --dart-define-from-file=env.json).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
