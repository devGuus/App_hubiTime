/// Guarda a sessão do Supabase no armazenamento seguro do sistema
/// (Keystore no Android, Keychain no iOS) em vez de SharedPreferences.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = supabasePersistSessionKey;
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _storage.read(key: _key)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
