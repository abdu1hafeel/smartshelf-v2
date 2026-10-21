// ==============================================================================
// SmartShelf V2 - Supabase Configuration Invariants & Security Unit Tests
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/config/supabase_config.dart';

void main() {
  group('SupabaseConfig Security & Invariant Tests', () {
    test('Default environment in test runtime does not force cloud credentials', () {
      // In normal unit test run without --dart-define, environment is empty
      expect(SupabaseConfig.environment, isEmpty);
    });

    test('Local development URL fallback resolves to valid local address', () {
      final url = SupabaseConfig.defaultUrl;
      expect(url, isNotEmpty);
      expect(url.startsWith('http://'), isTrue);
    });

    test('Local development anon key resolves to valid non-empty string', () {
      final key = SupabaseConfig.anonKey;
      expect(key, isNotEmpty);
      expect(key.startsWith('eyJ'), isTrue);
    });
  });
}
