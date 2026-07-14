import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/models/scanner_user.dart';
import 'package:kadenz_scanner/screens/login_screen.dart';
import 'package:kadenz_scanner/services/auth_service.dart';

/// In-memory AuthService for widget tests. Avoids `flutter_secure_storage`
/// (platform channels) and any network. `signIn` behaviour is configurable
/// via constructor flags.
class _FakeAuthService extends AuthService {
  _FakeAuthService({
    this.signInError,
    this.signInThrows,
    this.signInGate,
    this.baseUrlValue = 'https://kadenz.live',
  });

  final AuthException? signInError;
  final Object? signInThrows;
  final Completer<void>? signInGate;
  final String baseUrlValue;
  int signInCalls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<String> baseUrl() async => baseUrlValue;

  // PR #413 introduced a richer `resolveBaseUrl()` returning URL + source.
  // LoginScreen reads this directly, so the fake must provide it for the
  // subtitle to render.
  @override
  Future<ResolvedApiUrl> resolveBaseUrl() async =>
      ResolvedApiUrl(baseUrlValue, ApiUrlSource.defaultProd);

  // Stub the /healthz ping that LoginScreen runs after resolveBaseUrl —
  // without this override the real implementation hits `http.Client` and
  // tests log a "creates an HttpClient" warning + the banner gate stays
  // gated open longer than the test expects.
  @override
  Future<bool> isApiReachable({Duration timeout = const Duration(seconds: 4)}) async => true;

  @override
  Future<ScannerUser> signIn(String email, String password) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    if (signInGate != null) await signInGate!.future;
    if (signInError != null) throw signInError!;
    if (signInThrows != null) throw signInThrows!;
    return ScannerUser(id: 'u1', email: email, role: 'einlass');
  }
}

Widget _harness(_FakeAuthService auth, {LoginNextScreenBuilder? nextScreen}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: LoginScreen(
      authService: auth,
      nextScreenBuilder: nextScreen ??
          (_) => const Scaffold(body: Text('NEXT_STUB')),
    ),
  );
}

void main() {
  testWidgets('renders email + password fields + sign-in button', (tester) async {
    await tester.pumpWidget(_harness(_FakeAuthService()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows the resolved API base URL in the subtitle', (tester) async {
    await tester
        .pumpWidget(_harness(_FakeAuthService(baseUrlValue: 'https://kadenz.live')));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://kadenz.live'), findsOneWidget);
  });

  testWidgets('passes trimmed email + raw password to AuthService.signIn',
      (tester) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '  door@kadenz.live  ');
    await tester.enterText(find.byType(TextField).at(1), 'secret-pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(auth.lastEmail, 'door@kadenz.live');
    expect(auth.lastPassword, 'secret-pw');
  });

  testWidgets('navigates to next screen on successful sign-in', (tester) async {
    await tester.pumpWidget(_harness(_FakeAuthService()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('NEXT_STUB'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('surfaces AuthException messages inline (does not navigate)',
      (tester) async {
    final auth = _FakeAuthService(
        signInError: AuthException('Wrong credentials'));
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong credentials'), findsOneWidget);
    expect(find.text('NEXT_STUB'), findsNothing);
  });

  testWidgets('wraps non-AuthException errors with the connection-failure label',
      (tester) async {
    final auth = _FakeAuthService(signInThrows: Exception('SocketException'));
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connection failed'), findsOneWidget);
  });

  testWidgets('shows a spinner + disables the button while submitting',
      (tester) async {
    final gate = Completer<void>();
    final auth = _FakeAuthService(signInGate: gate);
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
