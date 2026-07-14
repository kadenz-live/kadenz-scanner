import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'theme/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KadenzScannerApp());
}

class KadenzScannerApp extends StatelessWidget {
  const KadenzScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kadenz Scanner',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de'),
        Locale('en'),
      ],
      localeResolutionCallback: (locale, supported) {
        if (locale != null) {
          for (final s in supported) {
            if (s.languageCode == locale.languageCode) return s;
          }
        }
        return const Locale('de');
      },
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: KadenzBrand.darkScheme(),
        scaffoldBackgroundColor: KadenzBrand.canvasDark,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      home: SplashScreen(authService: AuthService()),
    );
  }
}
