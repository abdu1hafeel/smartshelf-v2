// ==============================================================================
// SmartShelf V2 - Organization Model Unit Tests
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/organization.dart';

void main() {
  group('Organization Model Tests', () {
    test('fromJson deserializes valid JSON correctly', () {
      final json = {
        'id': '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        'name': 'SAHARA',
        'created_at': '2026-10-15T12:00:00Z',
      };

      final org = Organization.fromJson(json);

      expect(org.id, '2c17c6c2-83fc-453a-b2e2-8ec289795e3b');
      expect(org.name, 'SAHARA');
      expect(org.createdAt, DateTime.parse('2026-10-15T12:00:00Z'));
    });

    test('shortId returns first 8 characters of UUID', () {
      final org = Organization(
        id: '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );

      expect(org.shortId, '2c17c6c2');
    });

    test('shortId handles short non-UUID IDs gracefully', () {
      final org = Organization(
        id: 'abc',
        name: 'Short Org',
        createdAt: DateTime.now(),
      );

      expect(org.shortId, 'abc');
    });

    test('displayName returns plain name when isDuplicate is false', () {
      final org = Organization(
        id: '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );

      expect(org.displayName(isDuplicate: false), 'SAHARA');
      expect(org.displayName(), 'SAHARA');
    });

    test('displayName appends shortId when isDuplicate is true', () {
      final org1 = Organization(
        id: '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );
      final org2 = Organization(
        id: '432ab506-1111-2222-3333-444455556666',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );

      expect(org1.displayName(isDuplicate: true), 'SAHARA (2c17c6c2)');
      expect(org2.displayName(isDuplicate: true), 'SAHARA (432ab506)');
    });

    test('toJson serializes correctly', () {
      final now = DateTime.parse('2026-10-15T12:00:00.000Z');
      final org = Organization(
        id: 'org-1234-uuid',
        name: 'Retail Group',
        createdAt: now,
      );

      final json = org.toJson();

      expect(json['id'], 'org-1234-uuid');
      expect(json['name'], 'Retail Group');
      expect(json['created_at'], now.toIso8601String());
    });
  });
}
