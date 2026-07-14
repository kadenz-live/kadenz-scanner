import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/theme/brand.dart';

void main() {
  group('KadenzBrand', () {
    test('primary matches violet #7C3AED', () {
      expect(KadenzBrand.primary.toARGB32(), 0xFF7C3AED);
    });

    test('accent matches cyan #22D3EE', () {
      expect(KadenzBrand.accent.toARGB32(), 0xFF22D3EE);
    });

    test('darkScheme is Material 3 seeded from primary in dark brightness', () {
      final scheme = KadenzBrand.darkScheme();
      expect(scheme.brightness, Brightness.dark);
      // Seeded schemes derive a tonal palette — primary tone shifts but
      // remains in the violet hue family. Smoke-check: not white, not black.
      expect(scheme.primary, isNot(equals(const Color(0xFFFFFFFF))));
      expect(scheme.primary, isNot(equals(const Color(0xFF000000))));
    });
  });
}
