/// Tema claro/escuro. Cores de marca iguais às do site (globals.css).
library;

import 'package:flutter/material.dart';

const brandPrimary = Color(0xFF2A78D6);
const brandSuccess = Color(0xFF059669);
const brandWarning = Color(0xFFD97706);

/// Cores semânticas que o Material não tem (sucesso/alerta), por brilho.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  @override
  StatusColors copyWith({Color? success, Color? warning}) =>
      StatusColors(success: success ?? this.success, warning: warning ?? this.warning);

  @override
  StatusColors lerp(StatusColors? other, double t) => other == null
      ? this
      : StatusColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: brandPrimary, brightness: brightness).copyWith(primary: brandPrimary);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    // Alvos de toque de 48dp em qualquer tamanho de tela.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: [
      StatusColors(
        // No tema escuro o tom precisa ser mais claro para manter contraste sobre a superfície.
        success: dark ? const Color(0xFF34D399) : brandSuccess,
        warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      ),
    ],
  );
}

extension ThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}

/// Duração de animação que respeita "remover animações" do sistema
/// (movimento reduzido): vira zero quando o usuário desliga as animações.
Duration motion(BuildContext context, [int milliseconds = 200]) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : Duration(milliseconds: milliseconds);
