import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/config.dart';
import 'data/secure_session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isSupabaseConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  final prefs = await SharedPreferences.getInstance();

  runApp(
    HubiTimeApp(
      session: SessionController(Supabase.instance.client),
      theme: ThemeController(prefs),
    ),
  );
}
