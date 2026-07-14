// Widget tests for LoginScreen banner behaviour: it must surface API
// unreachability loudly (amber banner with i18n strings), not silently.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/screens/login_screen.dart';
import 'package:kadenz_scanner/screens/settings_screen.dart';
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('de')],
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
  });

  group('LoginScreen API unreachable banner', () {
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

    testWidgets('renders amber banner when health check fails (non-200)',
        (tester) async {
      when(() => client.get(any()))
          .thenAnswer((_) async => http.Response('nope', 503));

      await tester.pumpWidget(_wrap(LoginScreen(authService: auth)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login.api_unreachable_banner')),
          findsOneWidget);
      expect(find.text('Server unreachable'), findsOneWidget);
    });

    testWidgets('does NOT render banner on healthy https endpoint',
        (tester) async {
      when(() => client.get(any()))
          .thenAnswer((_) async => http.Response('ok', 200));

      await tester.pumpWidget(_wrap(LoginScreen(authService: auth)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login.api_unreachable_banner')),
          findsNothing);
    });

    testWidgets('renders banner when resolved URL is non-https (insecure)',
        (tester) async {
      // Override the default to an http:// localhost URL — simulating a
      // dev build that forgot to set --dart-define. Even if /healthz is
      // OK, we still warn because production traffic over plain http is
      // never acceptable.
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'http://10.0.2.2:3000');
      when(() => client.get(any()))
          .thenAnswer((_) async => http.Response('ok', 200));

      await tester.pumpWidget(_wrap(LoginScreen(authService: auth)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login.api_unreachable_banner')),
          findsOneWidget);
    });
  });

  group('SettingsScreen surfaces resolved URL + source', () {
    late _MockSecureStorage storage;
    late AuthService auth;

    setUp(() {
      storage = _MockSecureStorage();
      auth = AuthService(storage: storage);
      when(() => storage.write(
              key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
    });

    testWidgets('shows default URL + "Source: default" when nothing set',
        (tester) async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      await tester.pumpWidget(_wrap(SettingsScreen(authService: auth)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings.resolved_card')), findsOneWidget);
      final urlWidget = tester.widget<Text>(
          find.byKey(const Key('settings.resolved_url')));
      expect(urlWidget.data, 'https://kadenz.live');
      final sourceWidget = tester.widget<Text>(
          find.byKey(const Key('settings.resolved_source')));
      expect(sourceWidget.data, 'Source: default');
    });

    testWidgets('shows stored override + "Source: stored override"',
        (tester) async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'https://staging.kadenz.live');

      await tester.pumpWidget(_wrap(SettingsScreen(authService: auth)));
      await tester.pumpAndSettle();

      final urlWidget = tester.widget<Text>(
          find.byKey(const Key('settings.resolved_url')));
      expect(urlWidget.data, 'https://staging.kadenz.live');
      final sourceWidget = tester.widget<Text>(
          find.byKey(const Key('settings.resolved_source')));
      expect(sourceWidget.data, 'Source: stored override');
    });
  });
}
