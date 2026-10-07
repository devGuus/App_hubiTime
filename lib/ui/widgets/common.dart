/// Componentes reutilizáveis: estados de carregamento/erro/vazio, botão com
/// progresso, avisos e container de largura máxima para tablets.
library;

import 'package:flutter/material.dart';

import '../../data/errors.dart';
import '../theme.dart';

/// Centraliza o conteúdo e limita a largura em telas grandes (tablets).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Carregando...'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label,
          child: const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
        ),
      );
}

/// Estado de erro ou vazio, com ação opcional (ex.: "Tentar novamente").
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? context.colors.error : context.colors.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: color),
            const SizedBox(height: 12),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Faixa de aviso dentro da tela (offline, inconsistência, erro de sincronização).
class InlineBanner extends StatelessWidget {
  const InlineBanner({super.key, required this.icon, required this.message, this.color, this.action});
  final IconData icon;
  final String message;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tone, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: context.text.bodyMedium)),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Botão cheio com estado "ocupado": desabilita (anti toque duplicado) e
/// mostra progresso enquanto a ação assíncrona roda.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon, this.tonal = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: motion(context, 150),
      child: busy
          ? const SizedBox(key: ValueKey('busy'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    );
    final action = busy ? null : onPressed;
    return tonal ? FilledButton.tonal(onPressed: action, child: child) : FilledButton(onPressed: action, child: child);
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? context.colors.errorContainer : null,
      duration: Duration(seconds: error ? 6 : 3),
    ),
  );
}

String messageOf(Object error) => error is AppException ? error.message : 'Ocorreu um erro inesperado. Tente novamente.';

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: ctx.colors.error, foregroundColor: ctx.colors.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Semantics(header: true, child: Text(text, style: context.text.titleSmall?.copyWith(color: context.colors.onSurfaceVariant))),
      );
}
