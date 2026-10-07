/// Erros da camada de dados. A UI só mostra [AppException.message]; o detalhe
/// técnico fica no log e nunca vai para a tela.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AppException implements Exception {
  const AppException(this.message, {this.technical});
  final String message;
  final String? technical;
  @override
  String toString() => message;
}

/// Sem rede ou servidor inalcançável: nada foi salvo.
class OfflineException extends AppException {
  const OfflineException()
      : super('Sem conexão com a internet. Nada foi salvo no servidor.');
}

/// O registro mudou em outro lugar (site ou outro aparelho) desde que foi lido.
class ConflictException extends AppException {
  const ConflictException()
      : super('Este registro foi alterado em outro lugar. Recarregamos o dia — confira e tente novamente.');
}

/// Já existe registro para a data (unique user_id + work_date).
class DuplicateRecordException extends AppException {
  const DuplicateRecordException() : super('Já existe um registro para este dia.');
}

class SessionExpiredException extends AppException {
  const SessionExpiredException() : super('Sua sessão expirou. Entre novamente.');
}

const _authMessages = <(String, String)>[
  ('invalid login credentials', 'E-mail ou senha incorretos.'),
  ('email not confirmed', 'Seu e-mail ainda não foi confirmado. Confirme pelo site e tente de novo.'),
  ('email rate limit exceeded', 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.'),
  ('over_email_send_rate_limit', 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.'),
  ('too many requests', 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.'),
  ('user not found', 'Não encontramos uma conta com este e-mail.'),
];

String translateAuthMessage(String message) {
  final lowered = message.toLowerCase();
  for (final (fragment, friendly) in _authMessages) {
    if (lowered.contains(fragment)) return friendly;
  }
  return 'Não foi possível concluir a operação. Verifique os dados e tente novamente.';
}

bool _isNetworkError(Object e) =>
    e is SocketException ||
    e is http.ClientException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is AuthRetryableFetchException;

/// Converte qualquer erro vindo do Supabase em [AppException].
AppException translateError(Object error, String operation) {
  if (error is AppException) return error;
  debugPrint('Erro em "$operation": $error');
  if (_isNetworkError(error)) return const OfflineException();
  if (error is AuthException) {
    final jwt = error.message.toLowerCase().contains('jwt');
    if (jwt || error.statusCode == '401') return const SessionExpiredException();
    return AppException(translateAuthMessage(error.message), technical: error.message);
  }
  if (error is PostgrestException) {
    if (error.code == '23505') return const DuplicateRecordException();
    if (error.code == 'PGRST301' || error.code == 'PGRST303') return const SessionExpiredException();
    if (error.code == '42501') {
      return AppException('Sem permissão para esta operação.', technical: error.message);
    }
    return AppException(
      'Ocorreu um erro ao acessar seus dados. Tente novamente em instantes.',
      technical: error.message,
    );
  }
  return AppException('Ocorreu um erro inesperado ao $operation.', technical: error.toString());
}

/// Executa [action] traduzindo qualquer exceção para [AppException].
Future<T> guard<T>(String operation, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    throw translateError(e, operation);
  }
}
