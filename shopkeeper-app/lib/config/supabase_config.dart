// ==============================================================================
// SmartShelf V2 - Supabase Configuration
// ==============================================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  /// Compile-time configuration flags
  static const String environment =
      String.fromEnvironment('ENVIRONMENT', defaultValue: '');
  static const String _rawUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _rawAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Local development fallback constants (used ONLY in non-staging debug/test mode)
  static const String _localDevUrl = 'http://127.0.0.1:54321';
  static const String _localDevAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  static String? initializationError;

  /// Returns whether this build targets a non-local cloud environment (staging, production, or release mode)
  static bool get requiresCloudCredentials {
    final env = environment.toLowerCase().trim();
    return env == 'staging' || env == 'production' || kReleaseMode;
  }

  /// Resolved effective Supabase URL.
  /// Strictly requires compile-time SUPABASE_URL in staging or release mode.
  static String get defaultUrl {
    if (_rawUrl.isNotEmpty) {
      final url = _rawUrl.trim();
      if (requiresCloudCredentials &&
          (url.contains('127.0.0.1') || url.contains('localhost'))) {
        throw StateError(
          'Security violation: Localhost URL ($url) is forbidden in $environment or release builds.',
        );
      }
      return url;
    }

    if (requiresCloudCredentials) {
      throw StateError(
        'Missing required compile-time SUPABASE_URL for $environment build. '
        'Provide --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co',
      );
    }

    return _localDevUrl;
  }

  /// Resolved effective Supabase Public Anon/Publishable Key.
  /// Strictly requires compile-time SUPABASE_ANON_KEY in staging or release mode.
  static String get anonKey {
    if (_rawAnonKey.isNotEmpty) {
      final key = _rawAnonKey.trim();
      _assertNotServiceRoleKey(key);
      return key;
    }

    if (requiresCloudCredentials) {
      throw StateError(
        'Missing required compile-time SUPABASE_ANON_KEY for $environment build. '
        'Provide --dart-define=SUPABASE_ANON_KEY=<public-anon-key>',
      );
    }

    return _localDevAnonKey;
  }

  /// Validates that a service-role secret key is NEVER embedded in the client application.
  static void _assertNotServiceRoleKey(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('service_role') ||
        lower.contains('secret') ||
        lower.startsWith('sbp_')) {
      throw StateError(
        'CRITICAL SECURITY ERROR: A service-role or secret key was provided to the Flutter mobile application! '
        'Only public anon or publishable keys are permitted in client-side applications.',
      );
    }
  }

  /// Initializes Supabase for the shopkeeper application.
  static Future<void> initialize({
    String? customUrl,
    String? customAnonKey,
  }) async {
    try {
      initializationError = null;
      final url = customUrl ?? defaultUrl;
      final key = customAnonKey ?? anonKey;

      _assertNotServiceRoleKey(key);

      await Supabase.initialize(
        url: url,
        // ignore: deprecated_member_use
        anonKey: key,
      );
    } catch (err) {
      initializationError = err.toString();
      rethrow;
    }
  }

  /// Global Supabase client instance accessor.
  static SupabaseClient get client => Supabase.instance.client;
}
