import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../site_link.dart';
import '../theme.dart';
import '../widgets/common.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final session = AppServices.of(context).session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(_email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = AppServices.of(context).session.loginNotice;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Semantics(
                          label: 'Hubi Time',
                          image: true,
                          excludeSemantics: true,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset('assets/images/logo.png', width: 128, height: 128),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Bem-vindo de volta', style: context.text.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'Entre com a mesma conta do site para continuar controlando sua jornada.',
                        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (notice != null) ...[
                        InlineBanner(icon: Icons.info_outline, message: notice, color: context.status.warning),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                        validator: (v) => v != null && _emailRe.hasMatch(v.trim()) ? null : 'Informe um e-mail válido.',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !_busy,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Informe a senha.' : null,
                      ),
                      AnimatedSize(
                        duration: motion(context),
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: InlineBanner(icon: Icons.error_outline, message: _error!),
                              ),
                      ),
                      const SizedBox(height: 20),
                      BusyButton(label: 'Entrar', busy: _busy, onPressed: _submit),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(onPressed: () => openSite(context, '/cadastro'), child: const Text('Criar conta no site')),
                          TextButton(onPressed: () => openSite(context, '/recuperar-senha'), child: const Text('Esqueci minha senha')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
