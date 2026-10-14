// ==============================================================================
// SmartShelf V2 - Supabase Configuration
// ==============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  /// Supabase API URL from compile-time environment or default local endpoint.
  ///
  /// For physical Android devices via USB tethering (using `adb reverse tcp:54321 tcp:54321`)
  /// and desktop/web/iOS local testing, the default loopback is `http://127.0.0.1:54321`.
  ///
  /// For Android emulator testing (without ADB reverse), supply the emulator host loopback:
  /// `--dart-define=SUPABASE_URL=http://10.0.2.2:54321`
  static String get defaultUrl {
    const fromEnv = String.fromEnvironment('SUPABASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    return 'http://127.0.0.1:54321';
  }

  /// Public Anonymous Key safe for client-side app execution.
  /// WARNING: Never embed service_role keys in mobile applications!
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );

  /// Initializes Supabase for the shopkeeper application.
  static Future<void> initialize({String? customUrl}) async {
    final url = customUrl ?? defaultUrl;
    await Supabase.initialize(
      url: url,
      // ignore: deprecated_member_use
      anonKey: anonKey,
    );
  }

  /// Global Supabase client instance accessor.
  static SupabaseClient get client => Supabase.instance.client;
}
