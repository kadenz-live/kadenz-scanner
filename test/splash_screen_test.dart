import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/scanner_user.dart';
import 'package:kadenz_scanner/screens/splash_screen.dart';
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:kadenz_scanner/theme/brand.dart';

class _UnauthFake extends AuthService {
  @override
  Future<ScannerUser?> currentUser() async => null;

  @override
  Future<String?> token() async => null;
}

class _AuthedFake extends AuthService {
  @override
  Future<ScannerUser?> currentUser() async =>
      ScannerUser(id: 'u1', email: 'door@kadenz.live', role: 'einlass');

  @override
  Future<String?> token() async => 'jwt-token';
}

Widget _harness(
  AuthService auth, {
  Duration minDisplay = Duration.zero,
  SplashRouteBuilder? loggedIn,
  SplashRouteBuilder? loggedOut,
}) {
  return MaterialApp(
    home: SplashScreen(
      authService: auth,
      minDisplay: minDisplay,
      loggedInBuilder: loggedIn ??
          (_) => const Scaffold(body: Text('LOGGED_IN_STUB')),
      loggedOutBuilder: loggedOut ??
          (_) => const Scaffold(body: Text('LOGGED_OUT_STUB')),
    ),
  );
}

void main() {
  testWidgets('renders Kadenz wordmark', (tester) async {
    await tester.pumpWidget(_harness(_UnauthFake(), minDisplay: const Duration(seconds: 30)));
    await tester.pump();

    final image = tester.widget<Image>(find.descendant(
      of: find.byType(SplashScreen),
      matching: find.byType(Image),
    ));
    final asset = image.image as AssetImage;
    expect(asset.assetName, 'assets/brand/wordmark.png');
  });

  testWidgets('uses brand purple as scaffold background', (tester) async {
    await tester.pumpWidget(_harness(_UnauthFake(), minDisplay: const Duration(seconds: 30)));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.descendant(
      of: find.byType(SplashScreen),
      matching: find.byType(Scaffold),
    ));
    expect(scaffold.backgroundColor, KadenzBrand.primary);
  });

  testWidgets('exposes a screen-reader label for the brand mark', (tester) async {
    await tester.pumpWidget(_harness(_UnauthFake(), minDisplay: const Duration(seconds: 30)));
    await tester.pump();

    expect(find.bySemanticsLabel('Kadenz Einlasskontrolle'), findsOneWidget);
  });

  testWidgets('honours minimum display duration before navigating', (tester) async {
    await tester.pumpWidget(_harness(_UnauthFake(), minDisplay: const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('LOGGED_OUT_STUB'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('LOGGED_OUT_STUB'), findsOneWidget);
  });

  testWidgets('navigates to logged-in route when token + user present', (tester) async {
    await tester.pumpWidget(_harness(_AuthedFake()));
    await tester.pumpAndSettle();

    expect(find.text('LOGGED_IN_STUB'), findsOneWidget);
    expect(find.text('LOGGED_OUT_STUB'), findsNothing);
  });

  testWidgets('respects reduce-motion (no pulsing opacity tween)', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _harness(_UnauthFake(), minDisplay: const Duration(seconds: 30)),
    ));
    await tester.pump();

    final fade = tester.widget<FadeTransition>(find.byKey(const ValueKey('kadenz_splash_pulse')));
    expect(fade.opacity.value, 1.0);
  });
}
