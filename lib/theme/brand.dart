import 'package:flutter/material.dart';

/// Kadenz brand tokens. Single source of truth — keep in sync with the
/// `--primary` HSL token in `web/frontend/src/index.css` and the
/// `flutter_launcher_icons` / `flutter_native_splash` colour values in
/// `pubspec.yaml`.
class KadenzBrand {
  KadenzBrand._();

  /// Primary violet (matches web `--primary` HSL(263 85% 65%) ≈ #7C3AED in the
  /// dark theme used across Kadenz product surfaces).
  static const Color primary = Color(0xFF7C3AED);

  /// Cyan accent (mirrors the icon mark dot).
  static const Color accent = Color(0xFF22D3EE);

  /// Deep canvas background for dark scaffolds.
  static const Color canvasDark = Color(0xFF0B0D12);

  /// Material 3 ColorScheme seeded from the brand primary. Dark-only —
  /// the scanner runs in low-light venues; a light scheme is not exposed.
  static ColorScheme darkScheme() => ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      );
}
