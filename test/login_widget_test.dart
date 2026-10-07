import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubi_time/app.dart';
import 'package:hubi_time/app_state.dart';
import 'package:hubi_time/ui/widgets/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Cliente apontando para um host inexistente: nenhum teste faz chamada de rede.
SessionController newSession() => SessionController(
      SupabaseClient('http://localhost:1', 'chave-de-teste', authOptions: const AuthClientOptions(autoRefreshToken: false)),
    );

Future<void> pumpApp(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: const Size(360, 740), textScaler: TextScaler.linear(textScale)),
      child: HubiTimeApp(session: newSession(), theme: ThemeController(null)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem sessão mostra o login em português', (tester) async {
    await pumpApp(tester);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('valida e-mail e senha antes de chamar o servidor', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(find.text('Informe a senha.'), findsOneWidget);
  });

  testWidgets('layout do login não estoura com fonte grande (200%)', (tester) async {
    await pumpApp(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('tema escuro e movimento reduzido renderizam sem erro', (tester) async {
    final theme = ThemeController(null);
    await theme.setMode(ThemeMode.dark);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 1200), disableAnimations: true),
        child: HubiTimeApp(session: newSession(), theme: theme),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('StateMessage mostra ação de tentar novamente', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StateMessage(icon: Icons.cloud_off, title: 'Sem conexão', actionLabel: 'Tentar novamente', onAction: () => tapped = true),
      ),
    ));
    await tester.tap(find.text('Tentar novamente'));
    expect(tapped, true);
  });
}
