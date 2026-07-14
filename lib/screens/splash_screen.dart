import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/brand.dart';
import 'login_screen.dart';
import 'event_picker_screen.dart';

typedef SplashRouteBuilder = Widget Function(AuthService auth);

Widget _defaultLoggedIn(AuthService a) => EventPickerScreen(authService: a);
Widget _defaultLoggedOut(AuthService a) => LoginScreen(authService: a);

/// First screen on app launch. Renders the Kadenz wordmark on the brand
/// canvas for at least [minDisplay] (so the native splash-to-Flutter
/// transition reads as one coherent moment) while it resolves the stored
/// session, then pushes either the event picker or the login screen via
/// [loggedInBuilder] / [loggedOutBuilder] — these are injectable for tests.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.authService,
    SplashRouteBuilder loggedInBuilder = _defaultLoggedIn,
    SplashRouteBuilder loggedOutBuilder = _defaultLoggedOut,
    this.minDisplay = const Duration(milliseconds: 700),
  })  : _loggedInBuilder = loggedInBuilder,
        _loggedOutBuilder = loggedOutBuilder;

  final AuthService authService;
  final SplashRouteBuilder _loggedInBuilder;
  final SplashRouteBuilder _loggedOutBuilder;
  final Duration minDisplay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _minDisplayTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _resolve();
  }

  Future<void> _resolve() async {
    final auth = Future.wait([
      widget.authService.currentUser(),
      widget.authService.token(),
    ]);
    // Wrap the min-display delay in a cancellable Timer so dispose() can
    // tear it down without leaking a pending Future into the test runtime.
    final minDelay = Completer<void>();
    _minDisplayTimer = Timer(widget.minDisplay, () {
      if (!minDelay.isCompleted) minDelay.complete();
    });

    final pair = await auth;
    await minDelay.future;
    if (!mounted) return;

    final user = pair[0];
    final token = pair[1];
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => (user != null && token != null)
          ? widget._loggedInBuilder(widget.authService)
          : widget._loggedOutBuilder(widget.authService),
    ));
  }

  @override
  void dispose() {
    _minDisplayTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: KadenzBrand.primary,
      body: Semantics(
        label: 'Kadenz Einlasskontrolle',
        child: Center(
          child: FadeTransition(
            key: const ValueKey('kadenz_splash_pulse'),
            opacity: reduceMotion
                ? const AlwaysStoppedAnimation<double>(1.0)
                : Tween<double>(begin: 0.55, end: 1.0).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
            child: Image.asset(
              'assets/brand/wordmark.png',
              width: 280,
              fit: BoxFit.contain,
              semanticLabel: 'Kadenz',
            ),
          ),
        ),
      ),
    );
  }
}
