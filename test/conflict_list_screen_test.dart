import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/screens/conflict_list_screen.dart';

Widget _harness(ReconcileResult result) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ConflictListScreen(result: result),
    );

void main() {
  testWidgets('a clean reconcile says so instead of showing an empty list',
      (tester) async {
    await tester.pumpWidget(
      _harness(const ReconcileResult(acceptedCount: 12, conflicts: [])),
    );

    expect(find.text('12 accepted · 0 conflict(s)'), findsOneWidget);
    expect(find.text('No conflicts — all offline scans accepted.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('a double scan names both devices and the time', (tester) async {
    await tester.pumpWidget(
      _harness(ReconcileResult(
        acceptedCount: 3,
        conflicts: [
          ReconcileConflict(
            ticketId: 't1',
            reason: 'already_used',
            ticketCode: 'TIX-AAA1111',
            deviceId: 'door-b',
            alreadyCheckedInBy: 'door-a',
            alreadyCheckedInAt: DateTime.utc(2026, 6, 1, 20, 15),
          ),
        ],
      )),
    );

    expect(find.text('3 accepted · 1 conflict(s)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Double scan'), findsOneWidget);
    expect(find.text('Ticket TIX-AAA1111'), findsOneWidget);
    expect(find.textContaining('door-a'), findsOneWidget);
    expect(find.textContaining('door-b'), findsOneWidget);
  });

  testWidgets('the other server reasons get their own labels', (tester) async {
    await tester.pumpWidget(
      _harness(const ReconcileResult(
        acceptedCount: 0,
        conflicts: [
          ReconcileConflict(ticketId: 't1', reason: 'not_eligible'),
          ReconcileConflict(ticketId: 't2', reason: 'unknown'),
          // A status the app has not learned yet must still render something
          // the operator can read back over the radio, not crash the list.
          ReconcileConflict(ticketId: 't3', reason: 'server_invented_this'),
        ],
      )),
    );

    expect(find.text('Ticket not eligible'), findsOneWidget);
    expect(find.text('Unknown ticket'), findsOneWidget);
    expect(find.text('server_invented_this'), findsOneWidget);
    // No ticket code from the server: the raw id is shown rather than a blank.
    expect(find.text('Ticket t3'), findsOneWidget);
  });
}
