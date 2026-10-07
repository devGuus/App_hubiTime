import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/dates.dart';
import '../site_link.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  final initials = parts.map((p) => p[0].toUpperCase()).join();
  return initials.isEmpty ? '?' : initials;
}

/// Cor estável do avatar a partir do nome/e-mail (sem foto: a conta do site não tem).
Color _avatarColor(String seed) {
  final hue = seed.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor();
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final session = AppServices.of(context).session;
    final ok = await confirm(
      context,
      title: 'Sair da conta',
      message: 'Deseja realmente sair? Você precisará entrar de novo para registrar o ponto.',
      confirmLabel: 'Sair',
    );
    if (ok) await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppServices.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final email = session.user?.email ?? '';
        final name = session.profile?.name.trim() ?? '';
        final display = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Minha conta');
        final sub = session.subscription;
        return RefreshIndicator(
          onRefresh: session.refreshAccount,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(header: true, child: Text('Perfil', style: context.text.headlineSmall)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Semantics(
                          label: 'Avatar de $display',
                          excludeSemantics: true,
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: _avatarColor(display),
                            child: Text(_initialsOf(display), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(display, style: context.text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (email.isNotEmpty) Text(email, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (session.accountError != null) ...[
                      const SizedBox(height: 16),
                      InlineBanner(
                        icon: Icons.cloud_off,
                        message: 'Não foi possível carregar os dados da conta. ${session.accountError}',
                        action: TextButton(onPressed: session.refreshAccount, child: const Text('Tentar de novo')),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text('Seu plano', style: context.text.titleMedium),
                              const SizedBox(width: 8),
                              if (session.isPremium) Icon(Icons.verified, size: 18, color: context.status.success),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              session.isPremium
                                  ? 'Plano pago ativo até ${formatDateBR(sub!.currentPeriodEnd)}.'
                                  : 'Plano Free. Exportar relatórios e importar registros são recursos dos planos pagos.',
                            ),
                            const SizedBox(height: 4),
                            Text('A assinatura é gerenciada no site.', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => openSite(context),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir o site do Hubi Time'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _signOut(context),
                      style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sair da conta'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
