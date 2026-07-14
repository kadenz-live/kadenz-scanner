import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/scanner_event.dart';
import 'package:kadenz_scanner/models/scanner_user.dart';
import 'package:kadenz_scanner/models/validation_result.dart';

void main() {
  group('ScannerUser', () {
    test('parses JSON', () {
      final u = ScannerUser.fromJson({
        'id': 'abc',
        'email': 'scan@example.com',
        'role': 'scanner',
        'first_name': 'Scan',
        'last_name': 'Op',
      });
      expect(u.role, 'scanner');
      expect(u.displayName, 'Scan Op');
    });

    test('falls back to email when name is empty', () {
      final u = ScannerUser.fromJson({
        'id': 'a',
        'email': 'only@example.com',
        'role': 'admin',
      });
      expect(u.displayName, 'only@example.com');
    });
  });

  group('ScannerEvent', () {
    test('parses JSON', () {
      final e = ScannerEvent.fromJson({
        'id': 'evt-1',
        'title': 'Concert',
        'starts_at': '2030-01-01T20:00:00Z',
        'venue': 'Hafenklang',
        'tickets_total': 100,
        'tickets_used': 5,
      });
      expect(e.title, 'Concert');
      expect(e.startsAt.year, 2030);
      expect(e.ticketsUsed, 5);
    });
  });

  group('ValidationResult', () {
    test('extracts ticket info from a successful response', () {
      final r = ValidationResult.fromJson({
        'ok': true,
        'status': 'ok',
        'message': 'Valid',
        'ticket': {
          'code': 'TIX-ABC',
          'holder_name': 'Anna Beispiel',
          'ticket_type': {'name': 'Standard'},
          'event': {'title': 'Concert'},
        },
      });
      expect(r.ok, true);
      expect(r.code, 'TIX-ABC');
      expect(r.holderName, 'Anna Beispiel');
      expect(r.ticketTypeName, 'Standard');
      expect(r.eventTitle, 'Concert');
    });

    test('handles error responses without a ticket', () {
      final r = ValidationResult.fromJson({
        'ok': false,
        'status': 'invalid_signature',
        'message': 'Invalid',
      });
      expect(r.ok, false);
      expect(r.code, '');
      expect(r.status, 'invalid_signature');
    });
  });
}
