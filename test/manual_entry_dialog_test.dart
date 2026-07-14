import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/screens/manual_entry_dialog.dart';

void main() {
  group('normaliseManualCode', () {
    test('uppercases input', () {
      expect(normaliseManualCode('tix-abc1234'), 'TIX-ABC1234');
    });

    test('strips spaces between segments', () {
      expect(normaliseManualCode('TIX - ABC 1234'), 'TIX-ABC1234');
    });

    test('strips em/en-dashes inside the value', () {
      // operator pasted a code copied from a Word doc with smart-dashes
      expect(normaliseManualCode('TIX—ABC1234'), 'TIXABC1234');
    });
  });

  group('isLikelyTicketCode', () {
    test('accepts a canonical TIX code', () {
      expect(isLikelyTicketCode('TIX-ABC1234'), true);
    });

    test('rejects an empty string', () {
      expect(isLikelyTicketCode(''), false);
    });

    test('rejects a too-short tail', () {
      expect(isLikelyTicketCode('TIX-ABC'), false);
    });

    test('rejects a code without the TIX prefix', () {
      expect(isLikelyTicketCode('ABC123456'), false);
    });

    test('accepts user input with stray spaces / lowercase (pre-normalised)', () {
      expect(isLikelyTicketCode('tix - abc1234'), true);
    });
  });

  group('ManualEntryDialog widget', () {
    Widget harness({void Function(String?)? onClose}) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final value = await ManualEntryDialog.show(context);
                  if (onClose != null) onClose(value);
                },
                child: const Text('open'),
              ),
            ),
          );
        }),
      );
    }

    testWidgets('Validate button is disabled until input matches a TIX code',
        (tester) async {
      String? captured;
      await tester.pumpWidget(harness(onClose: (v) => captured = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final validateButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Validate'),
      );
      expect(validateButton.onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('manual_entry_field')),
          'tix-abc1234');
      await tester.pump();

      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Validate'),
      );
      expect(enabled.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pumpAndSettle();
      expect(captured, 'TIX-ABC1234');
    });

    testWidgets('Cancel returns null', (tester) async {
      String? captured = 'sentinel';
      await tester.pumpWidget(harness(onClose: (v) => captured = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(captured, isNull);
    });
  });
}
