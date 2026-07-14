import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadenz_scanner/services/api_service.dart';

/// Fail-safe parsing gate for validate / validate_code responses.
///
/// The door decision must never admit on anything other than a genuine 2xx
/// with a well-formed JSON object. Non-2xx, empty, or garbled bodies must be
/// explicit rejections so the operator does not let someone in on a broken or
/// changed server envelope.
void main() {
  group('ApiService.parseValidation fail-safe', () {
    test('2xx with ok:true and a well-formed body admits', () {
      final res = http.Response(
        '{"ok":true,"status":"ok","message":"OK","ticket":{"id":"t1"}}',
        200,
      );
      final r = ApiService.parseValidation(res);
      expect(r.ok, true);
      expect(r.status, 'ok');
    });

    test('non-2xx never admits, even if the body says ok:true', () {
      // A proxy/error page could still carry a stale ok:true envelope.
      final res = http.Response('{"ok":true,"status":"ok"}', 502);
      final r = ApiService.parseValidation(res);
      expect(r.ok, false);
      expect(r.status, 'server_error');
      expect(r.message, contains('502'));
    });

    test('401/403 is rejected, not admitted', () {
      for (final code in [401, 403]) {
        final r = ApiService.parseValidation(http.Response('', code));
        expect(r.ok, false, reason: 'status $code must reject');
        expect(r.status, 'server_error');
      }
    });

    test('2xx with an empty body is rejected, not silently admitted', () {
      final r = ApiService.parseValidation(http.Response('', 200));
      expect(r.ok, false);
      expect(r.status, 'server_error');
    });

    test('2xx with a non-JSON / garbled body is rejected', () {
      final r = ApiService.parseValidation(http.Response('<html>oops</html>', 200));
      expect(r.ok, false);
      expect(r.status, 'server_error');
    });

    test('2xx with a JSON array (not an object) is rejected', () {
      final r = ApiService.parseValidation(http.Response('[1,2,3]', 200));
      expect(r.ok, false);
      expect(r.status, 'server_error');
    });

    test('2xx object missing the ok key defaults to reject (no admit)', () {
      // Envelope change: ok key renamed/dropped. Must not admit.
      final r = ApiService.parseValidation(http.Response('{"status":"ok"}', 200));
      expect(r.ok, false);
    });

    test('2xx with ok:false surfaces the server rejection status', () {
      final res = http.Response(
        '{"ok":false,"status":"revoked","message":"Ticket widerrufen"}',
        200,
      );
      final r = ApiService.parseValidation(res);
      expect(r.ok, false);
      expect(r.status, 'revoked');
    });
  });
}
