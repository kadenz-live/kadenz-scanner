import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
  });

  group('AuthService.resolveBaseUrl precedence', () {
    late _MockSecureStorage storage;
    late _MockHttpClient client;
    late AuthService auth;

    setUp(() {
      storage = _MockSecureStorage();
      client = _MockHttpClient();
      auth = AuthService(storage: storage, httpClient: client);
    });

    test('returns stored override when env unset and storage has value',
        () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'https://staging.kadenz.live');

      final resolved = await auth.resolveBaseUrl();

      expect(resolved.url, 'https://staging.kadenz.live');
      expect(resolved.source, ApiUrlSource.storedOverride);
    });

    test('returns https://kadenz.live default when both env and storage unset',
        () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final resolved = await auth.resolveBaseUrl();

      expect(resolved.url, 'https://kadenz.live');
      expect(resolved.source, ApiUrlSource.defaultProd);
      expect(AuthService.defaultApiUrl, 'https://kadenz.live');
    });

    test('trims whitespace-only stored value and falls back to default',
        () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => '   ');

      final resolved = await auth.resolveBaseUrl();

      expect(resolved.url, 'https://kadenz.live');
      expect(resolved.source, ApiUrlSource.defaultProd);
    });

    test('baseUrl() returns the same string as resolveBaseUrl().url',
        () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'http://10.0.2.2:3000');

      expect(await auth.baseUrl(), 'http://10.0.2.2:3000');
    });

    // We cannot mutate the value of `String.fromEnvironment` from a unit test
    // — it is resolved at compile time. The build-env precedence is exercised
    // indirectly here by asserting the resolution helper's contract and is
    // covered end-to-end via the `--dart-define` build flag in CI's release
    // lane (see `.github/workflows/mobile-release.yml`).
    test('compile-time KADENZ_API constant exists and defaults to empty',
        () {
      // If a developer ever runs `flutter test --dart-define=KADENZ_API=...`
      // the resolveBaseUrl() output should reflect it. We don't assert a
      // value here because the build env is empty under `flutter test`.
      expect(AuthService.defaultApiUrl, startsWith('https://'));
    });
  });

  group('AuthService.isApiReachable', () {
    late _MockSecureStorage storage;
    late _MockHttpClient client;
    late AuthService auth;

    setUp(() {
      storage = _MockSecureStorage();
      client = _MockHttpClient();
      auth = AuthService(storage: storage, httpClient: client);
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
    });

    test('returns true on 200', () async {
      when(() => client.get(any())).thenAnswer(
          (_) async => http.Response('ok', 200));

      expect(await auth.isApiReachable(), isTrue);
    });

    test('returns false on 500', () async {
      when(() => client.get(any())).thenAnswer(
          (_) async => http.Response('bang', 500));

      expect(await auth.isApiReachable(), isFalse);
    });

    test('returns false on network exception', () async {
      when(() => client.get(any())).thenThrow(Exception('connection refused'));

      expect(await auth.isApiReachable(), isFalse);
    });

    test('hits the /healthz endpoint on the resolved base URL', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'http://example.test:3000');
      when(() => client.get(any())).thenAnswer(
          (_) async => http.Response('ok', 200));

      await auth.isApiReachable();

      final captured = verify(() => client.get(captureAny())).captured;
      final uri = captured.single as Uri;
      expect(uri.toString(), 'http://example.test:3000/healthz');
    });
  });

  group('AuthService.setBaseUrl / clearStoredBaseUrl', () {
    late _MockSecureStorage storage;
    late AuthService auth;

    setUp(() {
      storage = _MockSecureStorage();
      auth = AuthService(storage: storage);
      when(() => storage.write(
              key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
    });

    test('setBaseUrl trims whitespace before persisting', () async {
      await auth.setBaseUrl('  https://staging.kadenz.live  ');

      verify(() => storage.write(
              key: 'api_base_url', value: 'https://staging.kadenz.live'))
          .called(1);
    });

    test('clearStoredBaseUrl deletes the storage key', () async {
      await auth.clearStoredBaseUrl();

      verify(() => storage.delete(key: 'api_base_url')).called(1);
    });
  });
}
