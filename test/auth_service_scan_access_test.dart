import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

/// kadenz#1816 — the authority model lives on the SERVER.
///
/// The scanner used to refuse any login whose `user.role` was not `'scanner'`
/// or `'admin'`. The server enum is `{ customer, scanner, global_admin }`, so
/// `'admin'` matched nothing, a global admin could not sign in, and an operator
/// with an `einlass` membership on the account whose events they work was
/// turned away — while `'scanner'`, the one role that passed, was exactly the
/// role the API short-circuited to platform-wide scan authority.
///
/// These matrices are the mutation guard. The role column must not influence
/// the outcome at all; only the server's answer may. Re-introducing ANY
/// client-side role gate turns the first group red.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
  });

  const password = 'GateDemo!2026';
  const email = 'door@example.com';

  late _MockSecureStorage storage;
  late _MockHttpClient client;
  late AuthService auth;

  /// Every role string the server can emit, plus the two the OLD client gate
  /// happened to accept, plus values it never can — the point is that none of
  /// them may change the outcome.
  const roles = <String>[
    'customer', // an einlass member of an account: role stays `customer`
    'scanner', // the retired platform-wide role
    'global_admin', // rejected outright by the old gate
    'admin', // the string the old gate accepted and the server never emits
    'einlass', // not a user role at all (it is a membership role)
    '', // defensive: empty
  ];

  Map<String, dynamic> signInBody(String role) => {
        'user': {
          'id': 'u-1',
          'email': email,
          'role': role,
          'first_name': 'Door',
          'last_name': 'Staff',
        },
        'token': 'jwt-token-123',
      };

  void stubStorage() {
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((invocation) async {
      // A stable device id, and no stored base-url override.
      return invocation.namedArguments[#key] == 'device_id' ? 'dev-door-1' : null;
    });
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  }

  void stubSignIn(String role) {
    when(() => client.post(any(),
            headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response(jsonEncode(signInBody(role)), 200));
  }

  void stubProbe(int status, {String body = '{"events":[]}'}) {
    when(() => client.get(any(), headers: any(named: 'headers')))
        .thenAnswer((_) async => http.Response(body, status));
  }

  setUp(() {
    storage = _MockSecureStorage();
    client = _MockHttpClient();
    auth = AuthService(storage: storage, httpClient: client);
    stubStorage();
  });

  group('signIn accepts every role the server issues when the server allows it', () {
    for (final role in roles) {
      test('role="$role" + probe 200 => signed in', () async {
        stubSignIn(role);
        stubProbe(200);

        final user = await auth.signIn(email, password);

        expect(user.role, role);
        verify(() => storage.write(key: 'auth_token', value: 'jwt-token-123'))
            .called(1);
      });
    }
  });

  group('signIn refuses every role when the server answers 403', () {
    for (final role in roles) {
      test('role="$role" + probe 403 => AuthException, nothing persisted', () async {
        stubSignIn(role);
        stubProbe(403, body: '{"error":{"message":"forbidden"}}');

        await expectLater(
          auth.signIn(email, password),
          throwsA(isA<AuthException>()),
        );

        // A refused operator must not be left holding a usable token.
        verifyNever(() => storage.write(key: 'auth_token', value: any(named: 'value')));
        verifyNever(() => storage.write(key: 'auth_user', value: any(named: 'value')));
      });
    }
  });

  group('only 403 is an authorization answer', () {
    // A server fault is not a permission decision. Turning one into a login
    // refusal would lock door staff out during an outage at exactly the moment
    // they need to open the doors — a worse failure than the one #1816 fixes.
    for (final status in <int>[200, 204, 500, 502, 503, 404]) {
      test('probe $status => login proceeds', () async {
        stubSignIn('customer');
        stubProbe(status, body: status == 200 ? '{"events":[]}' : 'boom');

        await expectLater(auth.signIn(email, password), completes);
        verify(() => storage.write(key: 'auth_token', value: 'jwt-token-123'))
            .called(1);
      });
    }

    test('probe transport failure => login proceeds', () async {
      stubSignIn('customer');
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('connection reset'));

      await expectLater(auth.signIn(email, password), completes);
      verify(() => storage.write(key: 'auth_token', value: 'jwt-token-123'))
          .called(1);
    });
  });

  group('device binding', () {
    test('sign-in carries X-Device-Id so the API can bind it to the session',
        () async {
      stubSignIn('customer');
      stubProbe(200);

      await auth.signIn(email, password);

      final captured = verify(() => client.post(any(),
              headers: captureAny(named: 'headers'), body: any(named: 'body')))
          .captured
          .single as Map<String, String>;

      expect(captured['X-Device-Id'], 'dev-door-1');
      expect(captured['X-Kadenz-Client'], 'mobile-scanner/1.8.2');
    });

    test('the scan-access probe carries the bearer token and the device id',
        () async {
      stubSignIn('customer');
      stubProbe(200);

      await auth.signIn(email, password);

      final captured = verify(() =>
              client.get(any(), headers: captureAny(named: 'headers')))
          .captured
          .single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer jwt-token-123');
      expect(captured['X-Device-Id'], 'dev-door-1');
    });

    test('probes the scanner events endpoint on the resolved base URL', () async {
      stubSignIn('customer');
      stubProbe(200);

      await auth.signIn(email, password);

      final uri = verify(() =>
              client.get(captureAny(), headers: any(named: 'headers')))
          .captured
          .single as Uri;

      expect(uri.toString(), 'https://kadenz.live/api/v1/scanner/events');
    });
  });

  group('failures before the probe are unchanged', () {
    test('a non-2xx sign-in still surfaces the server error', () async {
      when(() => client.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response(
              '{"error":{"message":"Invalid Email or password."}}', 401));

      await expectLater(
        auth.signIn(email, password),
        throwsA(isA<AuthException>()),
      );
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });

    test('a 200 with no token is still a failure and never reaches the probe',
        () async {
      when(() => client.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response(
              jsonEncode({
                'user': {'id': 'u-1', 'email': email, 'role': 'customer'}
              }),
              200));

      await expectLater(
        auth.signIn(email, password),
        throwsA(isA<AuthException>()),
      );
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });
  });
}
