import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/models/validation_result.dart';
import 'package:kadenz_scanner/screens/scanner_status_labels.dart';

ValidationResult _r({required bool ok, required String status}) =>
    ValidationResult(ok: ok, status: status, message: '');

/// Resolves [AppLocalizations] for a given locale without spinning up a full
/// MaterialApp. AppLocalizations.delegate is a [LocalizationsDelegate]; calling
/// `load(locale)` synchronously returns the localized strings for that locale.
Future<AppLocalizations> _loc(Locale locale) async {
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('scannerStatusLabel — German door-staff copy', () {
    late AppLocalizations l;
    setUp(() async {
      l = await _loc(const Locale('de'));
    });

    test('ok → OK regardless of status code', () {
      expect(scannerStatusLabel(_r(ok: true, status: 'ok'), l), 'OK');
      expect(scannerStatusLabel(_r(ok: true, status: 'whatever'), l), 'OK');
    });

    test('already_used → BEREITS GENUTZT', () {
      expect(scannerStatusLabel(_r(ok: false, status: 'already_used'), l),
          'BEREITS GENUTZT');
    });

    test('void → UNGÜLTIG', () {
      expect(scannerStatusLabel(_r(ok: false, status: 'void'), l), 'UNGÜLTIG');
    });

    test('not_found → UNBEKANNT', () {
      expect(
          scannerStatusLabel(_r(ok: false, status: 'not_found'), l), 'UNBEKANNT');
    });

    test('network_error → KEIN NETZ', () {
      expect(scannerStatusLabel(_r(ok: false, status: 'network_error'), l),
          'KEIN NETZ');
    });

    test('unknown server-side status falls back to FEHLER (never raw enum)', () {
      expect(scannerStatusLabel(_r(ok: false, status: 'newly_added_status'), l),
          'FEHLER');
      expect(scannerStatusLabel(_r(ok: false, status: ''), l), 'FEHLER');
    });
  });

  group('scannerStatusLabel — English door-staff copy', () {
    late AppLocalizations l;
    setUp(() async {
      l = await _loc(const Locale('en'));
    });

    test('localises correctly under en locale', () {
      expect(scannerStatusLabel(_r(ok: true, status: 'ok'), l), 'OK');
      expect(scannerStatusLabel(_r(ok: false, status: 'already_used'), l),
          'ALREADY USED');
      expect(scannerStatusLabel(_r(ok: false, status: 'network_error'), l),
          'NO NETWORK');
      expect(scannerStatusLabel(_r(ok: false, status: 'unmapped'), l), 'ERROR');
    });
  });

  // Smoke test that confirms the EN + DE delegates resolve without throwing —
  // catches `flutter gen-l10n` regenerator drift before runtime.
  testWidgets('AppLocalizations loads for de + en', (tester) async {
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(de.scannerStatusOk, 'OK');
    expect(en.scannerStatusOk, 'OK');
    // Suppress the unused-import warning for flutter_localizations: it is
    // pulled in to ensure global delegates are resolvable in tests if a
    // future widget test wraps in MaterialApp.
    expect(GlobalMaterialLocalizations.delegate, isNotNull);
  });
}
