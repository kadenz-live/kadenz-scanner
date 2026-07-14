import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/validation_result.dart';
import 'package:kadenz_scanner/screens/scan_history.dart';

ValidationResult _r({required bool ok, String status = 'ok', String? id}) =>
    ValidationResult(
      ok: ok,
      status: status,
      message: '',
      ticket: id == null ? null : {'id': id},
    );

DateTime _t(int offsetMs) => DateTime(2026, 1, 1).add(Duration(milliseconds: offsetMs));

void main() {
  group('ScanHistory', () {
    test('starts empty', () {
      final h = ScanHistory();
      expect(h.isEmpty, true);
      expect(h.length, 0);
      expect(h.entries, isEmpty);
    });

    test('push prepends — most-recent first', () {
      final h = ScanHistory();
      h.push(_r(ok: true, id: 'a'), _t(0));
      h.push(_r(ok: true, id: 'b'), _t(3000));

      expect(h.length, 2);
      expect(h.entries[0].result.ticket!['id'], 'b');
      expect(h.entries[1].result.ticket!['id'], 'a');
    });

    test('respects capacity cap', () {
      final h = ScanHistory(capacity: 3);
      for (var i = 0; i < 5; i++) {
        h.push(_r(ok: true, id: 'tix-$i'), _t(i * 3000));
      }
      expect(h.length, 3);
      // most-recent three only
      expect(
        h.entries.map((e) => e.result.ticket!['id']).toList(),
        ['tix-4', 'tix-3', 'tix-2'],
      );
    });

    test('dedupes consecutive identical scans within 2 seconds', () {
      final h = ScanHistory();
      h.push(_r(ok: true, status: 'ok', id: 'tix-1'), _t(0));
      h.push(_r(ok: true, status: 'ok', id: 'tix-1'), _t(500));
      h.push(_r(ok: true, status: 'ok', id: 'tix-1'), _t(1900));

      expect(h.length, 1);
    });

    test('accepts a re-push of the same ticket after the dedupe window', () {
      final h = ScanHistory();
      h.push(_r(ok: false, status: 'already_used', id: 'tix-1'), _t(0));
      h.push(_r(ok: false, status: 'already_used', id: 'tix-1'), _t(3000));

      expect(h.length, 2);
    });

    test('does not dedupe when the status changes (even for the same ticket)', () {
      final h = ScanHistory();
      h.push(_r(ok: true, status: 'ok', id: 'tix-1'), _t(0));
      h.push(_r(ok: false, status: 'already_used', id: 'tix-1'), _t(500));

      expect(h.length, 2);
    });

    test('does not dedupe when the ticket id differs', () {
      final h = ScanHistory();
      h.push(_r(ok: true, status: 'ok', id: 'tix-a'), _t(0));
      h.push(_r(ok: true, status: 'ok', id: 'tix-b'), _t(500));

      expect(h.length, 2);
    });

    test('treats missing ticket ids as a stable empty key', () {
      // network_error rejections never carry a ticket — dedupe should still
      // collapse a rapid double-fire of the same error.
      final h = ScanHistory();
      h.push(_r(ok: false, status: 'network_error'), _t(0));
      h.push(_r(ok: false, status: 'network_error'), _t(800));
      expect(h.length, 1);
    });

    test('clear resets the buffer', () {
      final h = ScanHistory();
      h.push(_r(ok: true, id: 'a'), _t(0));
      h.clear();
      expect(h.isEmpty, true);
    });
  });
}
