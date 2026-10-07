/// Estado global: sessão do usuário, tema e repositórios.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/dates.dart';
import 'data/errors.dart';
import 'data/repositories.dart';
import 'domain/models.dart';

/// Tema do app: "seguir o sistema" é o padrão. Preferência só deste aparelho
/// (a coluna user_settings.theme do site só conhece claro/escuro e não é alterada).
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    final saved = _prefs?.getString(_key);
    _mode = ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  static const _key = 'theme_mode';
  final SharedPreferences? _prefs;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await _prefs?.setString(_key, mode.name);
  }
}

class SessionController extends ChangeNotifier {
  /// Os repositórios podem ser trocados em testes.
  SessionController(
    this.client, {
    WorkRepository? work,
    ScheduleRepository? schedule,
    SalaryRepository? salary,
    UserRepository? users,
  })  : work = work ?? WorkRepository(client),
        schedule = schedule ?? ScheduleRepository(client),
        salary = salary ?? SalaryRepository(client),
        users = users ?? UserRepository(client) {
    _user = client.auth.currentUser;
    _authSub = client.auth.onAuthStateChange.listen(_onAuthEvent);
    if (_user != null) unawaited(refreshAccount());
  }

  final SupabaseClient client;
  final WorkRepository work;
  final ScheduleRepository schedule;
  final SalaryRepository salary;
  final UserRepository users;

  StreamSubscription<AuthState>? _authSub;
  User? _user;
  Profile? _profile;
  UserSettings? _settings;
  Subscription? _subscription;
  bool _loadingAccount = false;
  String? _accountError;
  bool _signingOutByUser = false;

  /// Mensagem exibida no login quando a sessão acabou sem o usuário pedir.
  String? loginNotice;

  User? get user => _user;
  String get userId => _user!.id;
  Profile? get profile => _profile;
  UserSettings? get settings => _settings;
  bool get loadingAccount => _loadingAccount;
  String? get accountError => _accountError;
  bool get isSignedIn => _user != null;
  bool get isPremium => Subscription.isPremium(_subscription, todayIso());
  Subscription? get subscription => _subscription;

  void _onAuthEvent(AuthState state) {
    final previous = _user;
    _user = state.session?.user;
    if (state.event == AuthChangeEvent.signedOut) {
      _clearAccount();
      if (previous != null && !_signingOutByUser) {
        loginNotice = 'Sua sessão expirou. Entre novamente.';
      }
    } else if (_user != null && previous?.id != _user!.id) {
      unawaited(refreshAccount());
    }
    notifyListeners();
  }

  void _clearAccount() {
    _profile = null;
    _settings = null;
    _subscription = null;
    _accountError = null;
  }

  /// Carrega perfil, preferências e assinatura da conta autenticada.
  Future<void> refreshAccount() async {
    if (_user == null) return;
    _loadingAccount = true;
    _accountError = null;
    notifyListeners();
    try {
      final id = _user!.id;
      final results = await Future.wait([
        users.getProfile(id),
        users.getSettings(id),
        users.getSubscription(id),
      ]);
      _profile = results[0] as Profile?;
      _settings = results[1] as UserSettings?;
      _subscription = results[2] as Subscription?;
    } on AppException catch (e) {
      _accountError = e.message;
    } finally {
      _loadingAccount = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    loginNotice = null;
    await guard('entrar', () => client.auth.signInWithPassword(email: email.trim(), password: password));
  }

  /// Encerra a sessão local imediatamente (mesmo offline). A revogação no
  /// servidor é feita em seguida, sem bloquear.
  Future<void> signOut() async {
    _signingOutByUser = true;
    try {
      await client.auth.signOut();
    } catch (_) {
      // Offline: a sessão local já foi removida; o token expira sozinho no servidor.
    } finally {
      _signingOutByUser = false;
    }
  }

  /// Incrementa quando configurações que afetam os cálculos mudam, para telas
  /// já abertas (ex.: Ponto) recarregarem.
  int dataRevision = 0;

  void notifyDataChanged() {
    dataRevision++;
    notifyListeners();
  }

  Future<void> updateNotifications(Map<String, bool> notifications) async {
    await users.updateNotifications(userId, notifications);
    await refreshAccount();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

class AppServices extends InheritedWidget {
  const AppServices({super.key, required this.session, required this.theme, required super.child});

  final SessionController session;
  final ThemeController theme;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices não encontrado na árvore de widgets');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) => session != oldWidget.session || theme != oldWidget.theme;
}
