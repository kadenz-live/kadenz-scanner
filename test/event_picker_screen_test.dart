import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/models/scanner_event.dart';
import 'package:kadenz_scanner/models/scanner_user.dart';
import 'package:kadenz_scanner/screens/event_picker_screen.dart';
import 'package:kadenz_scanner/services/api_service.dart';
import 'package:kadenz_scanner/services/auth_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String> baseUrl() async => 'https://kadenz.live';

  @override
  Future<ScannerUser?> currentUser() async =>
      ScannerUser(id: 'u1', email: 'door@kadenz.live', role: 'einlass');

  @override
  Future<String?> token() async => 'jwt';

  @override
  Future<String> deviceId() async => 'device-test';
}

/// Minimal stub of [ApiService] that returns the supplied future from
/// `events()` and ignores every other endpoint. Tests pin behaviour by
/// passing either a resolved list, a deferred future, or one that throws.
class _FakeApi extends ApiService {
  _FakeApi({required this.eventsResult}) : super(_FakeAuth());

  final Future<List<ScannerEvent>> Function() eventsResult;

  @override
  Future<List<ScannerEvent>> events() => eventsResult();
}

ScannerEvent _evt({
  String id = 'ev-1',
  String title = 'Junkyard Night',
  String? venue = 'Junkyard Dortmund',
  int total = 200,
  int used = 12,
  DateTime? at,
}) {
  return ScannerEvent(
    id: id,
    title: title,
    startsAt: at ?? DateTime(2026, 6, 1, 20),
    venue: venue,
    ticketsTotal: total,
    ticketsUsed: used,
  );
}

Widget _harness(_FakeApi api) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: EventPickerScreen(authService: _FakeAuth(), api: api),
  );
}

void main() {
  testWidgets('shows a spinner while the events query is pending',
      (tester) async {
    final completer = Completer<List<ScannerEvent>>();
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () => completer.future)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the empty-state copy when the server returns zero events',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () async => [])));
    await tester.pumpAndSettle();

    expect(find.text('No upcoming events.'), findsOneWidget);
  });

  testWidgets('renders the load-error UI + a working retry button on failure',
      (tester) async {
    var attempt = 0;
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () async {
      attempt++;
      if (attempt == 1) throw Exception('boom');
      return <ScannerEvent>[];
    })));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No upcoming events.'), findsOneWidget);
    expect(attempt, 2);
  });

  testWidgets('renders one row per server event AND prepends the "Any event" tile',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () async => [
          _evt(),
          _evt(id: 'ev-2', title: 'Sundown Sessions', venue: 'Werkstatt'),
        ])));
    await tester.pumpAndSettle();

    expect(find.text('Junkyard Night'), findsOneWidget);
    expect(find.text('Sundown Sessions'), findsOneWidget);
    // "Any event" sentinel always present
    expect(find.text('Scan any event'), findsOneWidget);
  });

  testWidgets('shows live X/Y checked-in counts for each concrete event',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () async => [
          _evt(total: 200, used: 42),
        ])));
    await tester.pumpAndSettle();

    expect(find.text('42/200 checked in'), findsOneWidget);
  });

  testWidgets('omits venue separator when the venue field is null',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeApi(eventsResult: () async => [
          _evt(venue: null),
        ])));
    await tester.pumpAndSettle();

    expect(find.textContaining(' · '), findsNothing);
  });
}
