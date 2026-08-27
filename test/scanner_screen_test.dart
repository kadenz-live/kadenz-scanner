import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/audio/scan_audio.dart';
import 'package:kadenz_scanner/camera/scan_camera.dart';
import 'package:kadenz_scanner/l10n/app_localizations.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/models/queued_scan.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/models/scanner_event.dart';
import 'package:kadenz_scanner/models/validation_result.dart';
import 'package:kadenz_scanner/screens/conflict_list_screen.dart';
import 'package:kadenz_scanner/screens/scanner_screen.dart';
import 'package:kadenz_scanner/services/api_service.dart';
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_scan_camera.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String> baseUrl() async => 'https://kadenz.live';

  @override
  Future<String?> token() async => 'jwt';

  @override
  Future<String> deviceId() async => 'door-a';
}

/// Records what the screen asked the server to validate and replays a canned
/// verdict. Everything the screen does *not* call throws, so an accidental
/// extra round-trip shows up as a failure rather than silence.
class _FakeApi extends ApiService {
  _FakeApi({
    Future<ValidationResult> Function(String payload)? onValidate,
    this.onValidateByCode,
    this.manifestData,
    this.reconcileResponse,
  })  : onValidate = onValidate ?? _admit,
        super(_FakeAuth());

  static Future<ValidationResult> _admit(String payload) async =>
      ValidationResult(ok: true, status: 'ok', message: '');

  final Future<ValidationResult> Function(String payload) onValidate;
  final Future<ValidationResult> Function(String code)? onValidateByCode;
  final OfflineManifest? manifestData;
  final ReconcileResult? reconcileResponse;

  final List<String> validatedPayloads = <String>[];
  final List<String> validatedCodes = <String>[];
  List<QueuedScan>? reconciledWith;

  @override
  Future<ValidationResult> validate({required String payload, String? eventId}) {
    validatedPayloads.add(payload);
    return onValidate(payload);
  }

  @override
  Future<ValidationResult> validateByCode({
    required String eventId,
    required String code,
  }) {
    validatedCodes.add(code);
    final handler = onValidateByCode;
    if (handler == null) throw StateError('validateByCode not expected');
    return handler(code);
  }

  @override
  Future<OfflineManifest> manifest(String eventId) async {
    final data = manifestData;
    if (data == null) throw StateError('manifest not expected');
    return data;
  }

  @override
  Future<ReconcileResult> reconcile(String eventId, List<QueuedScan> scans) async {
    final response = reconcileResponse;
    if (response == null) throw StateError('reconcile not expected');
    reconciledWith = scans;
    return response;
  }
}

class _RecordingAudio extends ScanAudio {
  int successes = 0;
  int failures = 0;

  @override
  Future<void> playSuccess() async => successes++;

  @override
  Future<void> playFail() async => failures++;
}

ScannerEvent _event({int total = 200, int used = 12}) => ScannerEvent(
      id: 'evt-1',
      title: 'Junkyard Night',
      startsAt: DateTime(2026, 6, 1, 20),
      venue: 'Junkyard Dortmund',
      ticketsTotal: total,
      ticketsUsed: used,
    );

ValidationResult _ok({String holder = 'Ada Lovelace', String code = 'TIX-AAA1111'}) =>
    ValidationResult(
      ok: true,
      status: 'ok',
      message: '',
      ticket: {
        'id': 't1',
        'holder_name': holder,
        'code': code,
        'event': {'title': 'Junkyard Night'},
      },
    );

ValidationResult _reject(String status, {String message = ''}) =>
    ValidationResult(ok: false, status: status, message: message, ticket: {'id': 't1'});

Widget _harness({
  required _FakeApi api,
  required FakeScanCamera camera,
  ScannerEvent? event,
  ScanAudio? audio,
  AuthService? auth,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: ScannerScreen(
      api: api,
      event: event ?? _event(),
      authService: auth,
      audio: audio,
      cameraFactory: () => camera,
    ),
  );
}

/// Text inside the live result panel — never a stray match from the HUD or
/// the history strip.
Finder _inResult(String text) => find.descendant(
      of: find.byKey(const ValueKey('scanner_result')),
      matching: find.text(text),
    );

/// Substring match inside the result panel — the holder line is rendered as
/// `"<ticket type> · <holder>"`, so an exact finder would be brittle.
Finder _inResultContaining(String text) => find.descendant(
      of: find.byKey(const ValueKey('scanner_result')),
      matching: find.textContaining(text),
    );

/// Flush a SnackBar: ScaffoldMessenger queues them, so a later message stays
/// invisible until the current one has timed out.
Future<void> _flushSnack(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 5));

/// Deliver one detection and let the validation round-trip settle.
Future<void> _scan(WidgetTester tester, FakeScanCamera camera, String payload) async {
  camera.emit(payload);
  await tester.pumpAndSettle(const Duration(milliseconds: 1500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('camera wiring', () {
    testWidgets('starts the camera after the preview is mounted, never before',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));

      // The plugin rejects start() before its preview widget is attached, so
      // the screen must wait for the first frame.
      expect(find.byKey(const ValueKey('fake_camera_preview')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(camera.startCount, 1);
    });

    testWidgets('releases the camera when the screen goes away', (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(camera.disposeCount, 1);
    });

    testWidgets('stops on inactive and resumes on foreground', (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();
      final startsAfterMount = camera.startCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(camera.stopCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.startCount, startsAfterMount + 1);
    });

    testWidgets('a denied permission is not fought over on every resume',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();
      camera.raiseFault(ScanCameraFault.permissionDenied);
      await tester.pumpAndSettle();
      final startsBefore = camera.startCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(camera.startCount, startsBefore);
    });
  });

  group('door decisions', () {
    testWidgets('admits a valid ticket: green panel, success cue, HUD +1',
        (tester) async {
      final audio = _RecordingAudio();
      final api = _FakeApi(onValidate: (_) async => _ok());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, audio: audio, event: _event(used: 12)),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 / 200 checked in'), findsOneWidget);

      await _scan(tester, camera, 'signed.token.A');

      expect(api.validatedPayloads, ['signed.token.A']);
      expect(_inResult('OK'), findsOneWidget);
      expect(_inResultContaining('Ada Lovelace'), findsOneWidget);
      expect(_inResult('Junkyard Night'), findsOneWidget);
      expect(_inResult('TIX-AAA1111'), findsOneWidget);
      expect(audio.successes, 1);
      expect(audio.failures, 0);
      expect(find.text('13 / 200 checked in'), findsOneWidget);
    });

    testWidgets('rejects a forged token: no admit, no HUD movement, fail cue',
        (tester) async {
      final audio = _RecordingAudio();
      // A tampered QR fails the server-side HMAC check and comes back as a
      // hard rejection — the door must see VOID, not OK.
      final api = _FakeApi(
        onValidate: (_) async =>
            _reject('void', message: 'Signature mismatch'),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, audio: audio, event: _event(used: 12)),
      );
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'forged.token');

      expect(_inResult('VOID'), findsOneWidget);
      expect(_inResult('OK'), findsNothing);
      expect(audio.successes, 0);
      expect(audio.failures, 1);
      // A rejection must never move the checked-in counter.
      expect(find.text('12 / 200 checked in'), findsOneWidget);
    });

    testWidgets('an already-used ticket renders the amber warning verdict',
        (tester) async {
      final api = _FakeApi(onValidate: (_) async => _reject('already_used'));
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'used.token');

      expect(_inResult('ALREADY USED'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scanner_result')),
          matching: find.byIcon(Icons.error),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a network failure shows NO NETWORK instead of admitting',
        (tester) async {
      final audio = _RecordingAudio();
      final api = _FakeApi(
        onValidate: (_) async => throw Exception('connection closed'),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera, audio: audio));
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'any.token');

      expect(_inResult('NO NETWORK'), findsOneWidget);
      expect(audio.successes, 0);
      expect(audio.failures, 1);
    });

    testWidgets('the last three verdicts stay on screen as a history strip',
        (tester) async {
      var call = 0;
      final api = _FakeApi(onValidate: (_) async {
        call++;
        return _ok(holder: 'Holder $call', code: 'TIX-0000000$call');
      });
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'token.A');
      await _scan(tester, camera, 'token.B');

      expect(find.byKey(const ValueKey('scanner_history')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scanner_history')),
          matching: find.text('Holder 1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('double-scan guards', () {
    testWidgets('the same QR held in front of the lens validates once',
        (tester) async {
      final api = _FakeApi(onValidate: (_) async => _ok());
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'signed.token.A');
      // Same payload again, after the in-flight guard has already cleared:
      // only the debounce can stop this one.
      await _scan(tester, camera, 'signed.token.A');

      expect(api.validatedPayloads, ['signed.token.A']);
    });

    testWidgets('a different ticket right after is not swallowed',
        (tester) async {
      final api = _FakeApi(onValidate: (_) async => _ok());
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await _scan(tester, camera, 'signed.token.A');
      await _scan(tester, camera, 'signed.token.B');

      expect(api.validatedPayloads, ['signed.token.A', 'signed.token.B']);
    });

    testWidgets('a second ticket detected mid-validation is dropped, not queued',
        (tester) async {
      final gate = Completer<ValidationResult>();
      final api = _FakeApi(onValidate: (_) => gate.future);
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      camera.emit('signed.token.A');
      await tester.pump();
      // Different payload, so the debounce cannot mask this: only the
      // in-flight guard stands between it and a second server round-trip.
      camera.emit('signed.token.B');
      await tester.pump();

      expect(api.validatedPayloads, ['signed.token.A']);

      gate.complete(_ok());
      await tester.pumpAndSettle(const Duration(milliseconds: 1500));
    });
  });

  group('camera faults', () {
    testWidgets('a denied camera blocks the preview and explains the fix',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();

      camera.raiseFault(ScanCameraFault.permissionDenied);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fake_camera_preview')), findsNothing);
      expect(find.text('Camera access denied'), findsOneWidget);
      expect(find.text('Allow camera access in system settings.'), findsOneWidget);
      // Manual entry must survive a dead camera — otherwise the door stops.
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    });

    testWidgets('a device without a camera says so', (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();

      camera.raiseFault(ScanCameraFault.unsupported);
      await tester.pumpAndSettle();

      expect(find.text('No camera available'), findsOneWidget);
      expect(find.text('Use manual code entry.'), findsOneWidget);
    });

    testWidgets('retry restarts the camera and brings the preview back',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();
      camera.raiseFault(ScanCameraFault.unknown);
      await tester.pumpAndSettle();
      expect(find.text('Camera error'), findsOneWidget);
      final startsBefore = camera.startCount;

      await tester.tap(find.byKey(const ValueKey('scanner_camera_retry')));
      await tester.pumpAndSettle();

      expect(camera.startCount, startsBefore + 1);
      expect(find.byKey(const ValueKey('fake_camera_preview')), findsOneWidget);
    });
  });

  group('operator controls', () {
    testWidgets('the torch button reflects and toggles the torch',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.flashlight_off_outlined), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scanner_torch')));
      await tester.pumpAndSettle();

      expect(camera.torchToggleCount, 1);
      expect(find.byIcon(Icons.flashlight_on), findsOneWidget);
      expect(find.byIcon(Icons.flashlight_off_outlined), findsNothing);
    });

    testWidgets('a camera without a torch disables the button instead of '
        'pretending', (tester) async {
      final camera = FakeScanCamera(torch: ScanTorch.unavailable);
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('scanner_torch')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the camera-switch button flips facing and its icon',
        (tester) async {
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: _FakeApi(), camera: camera));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cameraswitch_outlined), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scanner_camera_switch')));
      await tester.pumpAndSettle();

      expect(camera.switchCameraCount, 1);
      expect(find.byIcon(Icons.camera_front_outlined), findsOneWidget);
    });

    testWidgets('manual entry runs through the same verdict panel',
        (tester) async {
      final api = _FakeApi(
        onValidateByCode: (_) async => _ok(holder: 'Grace Hopper'),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'TIX-AAA1111');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validate'));
      await tester.pumpAndSettle();

      expect(api.validatedCodes, ['TIX-AAA1111']);
      expect(_inResultContaining('Grace Hopper'), findsOneWidget);
    });

    testWidgets('a manual entry that cannot reach the server says NO NETWORK',
        (tester) async {
      final api = _FakeApi(
        onValidateByCode: (_) async => throw Exception('connection closed'),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(_harness(api: api, camera: camera));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'TIX-AAA1111');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validate'));
      await tester.pumpAndSettle();

      expect(_inResult('NO NETWORK'), findsOneWidget);
    });

    testWidgets('"any event" mode hides manual entry and counts scans',
        (tester) async {
      final api = _FakeApi(onValidate: (_) async => _ok());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ScannerScreen(
            api: api,
            event: null,
            cameraFactory: () => camera,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Any event'), findsOneWidget);
      // No event id means the manual-entry endpoint cannot be addressed.
      expect(find.byIcon(Icons.keyboard_outlined), findsNothing);

      await _scan(tester, camera, 'signed.token.A');
      expect(find.text('1 scanned'), findsOneWidget);
    });
  });

  group('offline mode', () {
    OfflineManifest manifest() => OfflineManifest(
          eventId: 'evt-1',
          eventTitle: 'Junkyard Night',
          generatedAt: DateTime.now().toUtc(),
          entries: [
            ManifestEntry(
              id: 't1',
              digest: OfflineManifest.digestOf('offline.token.A'),
              status: 'active',
            ),
            ManifestEntry(
              id: 't2',
              digest: OfflineManifest.digestOf('offline.token.B'),
              status: 'active',
            ),
          ],
        );

    Future<void> prepareAndGoOffline(
      WidgetTester tester,
    ) async {
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare offline mode'));
      await tester.pumpAndSettle();
      await _flushSnack(tester);
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start offline mode'));
      await tester.pumpAndSettle();
    }

    testWidgets('an offline scan is admitted locally and queued, no server call',
        (tester) async {
      final api = _FakeApi(manifestData: manifest());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare offline mode'));
      await tester.pumpAndSettle();
      expect(find.text('Offline manifest loaded: 2 tickets'), findsOneWidget);
      await _flushSnack(tester);

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start offline mode'));
      await tester.pumpAndSettle();
      expect(find.textContaining('OFFLINE – 0 scans queued'), findsOneWidget);

      await _scan(tester, camera, 'offline.token.A');

      expect(_inResult('OK'), findsOneWidget);
      // The whole point of offline mode: nothing left the device.
      expect(api.validatedPayloads, isEmpty);
      expect(find.textContaining('OFFLINE – 1 scans queued'), findsOneWidget);
    });

    testWidgets('an unknown token is refused offline and stays unqueued',
        (tester) async {
      final api = _FakeApi(manifestData: manifest());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);

      await _scan(tester, camera, 'not.in.manifest');

      expect(_inResult('UNKNOWN TICKET'), findsOneWidget);
      expect(find.textContaining('OFFLINE – 0 scans queued'), findsOneWidget);
    });

    testWidgets('the same ticket cannot be walked in twice offline',
        (tester) async {
      final api = _FakeApi(manifestData: manifest());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);

      await _scan(tester, camera, 'offline.token.A');
      // A different QR would be needed for a second admit; re-presenting the
      // same one must not add a second queue entry.
      await _scan(tester, camera, 'offline.token.B');
      await _scan(tester, camera, 'offline.token.A');

      expect(find.textContaining('OFFLINE – 2 scans queued'), findsOneWidget);
      expect(_inResult('ALREADY USED'), findsOneWidget);
    });

    testWidgets('a failed manifest sync is reported and offline stays off',
        (tester) async {
      // No manifest primed: _FakeApi throws, as an unreachable server would.
      final api = _FakeApi();
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare offline mode'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync failed'), findsOneWidget);
      // Without a manifest there is nothing to validate against, so the menu
      // must not offer offline mode.
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Start offline mode'), findsNothing);
      await tester.tapAt(const Offset(400, 500));
      await tester.pumpAndSettle();
    });

    testWidgets('leaving offline mode drops the banner and keeps the queue',
        (tester) async {
      final api = _FakeApi(manifestData: manifest());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);
      await _scan(tester, camera, 'offline.token.A');

      // The banner shows the same icon — target the app-bar menu explicitly.
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.cloud_off),
      ));
      await tester.pumpAndSettle();
      // The queued scan is still unreconciled, so the menu keeps offering it.
      expect(find.text('Reconcile (1)'), findsOneWidget);
      await tester.tap(find.text('Exit offline mode'));
      await tester.pumpAndSettle();

      expect(find.textContaining('OFFLINE'), findsNothing);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    });

    testWidgets('reconcile can also be triggered from the offline menu',
        (tester) async {
      final api = _FakeApi(
        manifestData: manifest(),
        reconcileResponse:
            const ReconcileResult(acceptedCount: 1, conflicts: []),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);
      await _scan(tester, camera, 'offline.token.A');

      // The banner shows the same icon — target the app-bar menu explicitly.
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.cloud_off),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconcile (1)'));
      await tester.pumpAndSettle();

      expect(api.reconciledWith, hasLength(1));
      expect(find.byType(ConflictListScreen), findsOneWidget);
      expect(find.text('No conflicts — all offline scans accepted.'),
          findsOneWidget);
    });

    testWidgets('reconcile pushes the queue and opens the conflict list',
        (tester) async {
      final api = _FakeApi(
        manifestData: manifest(),
        reconcileResponse: const ReconcileResult(
          acceptedCount: 1,
          conflicts: [
            ReconcileConflict(
              ticketId: 't1',
              reason: 'already_used',
              ticketCode: 'TIX-AAA1111',
              deviceId: 'door-b',
            ),
          ],
        ),
      );
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);
      await _scan(tester, camera, 'offline.token.A');

      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      expect(api.reconciledWith, hasLength(1));
      expect(api.reconciledWith?.first.ticketId, 't1');
      expect(find.byType(ConflictListScreen), findsOneWidget);
      expect(find.text('1 accepted · 1 conflict(s)'), findsOneWidget);
      expect(find.text('Double scan'), findsOneWidget);
      expect(find.text('Ticket TIX-AAA1111'), findsOneWidget);
    });

    testWidgets('a failed reconcile keeps the queue and says why',
        (tester) async {
      final api = _FakeApi(manifestData: manifest());
      final camera = FakeScanCamera();
      await tester.pumpWidget(
        _harness(api: api, camera: camera, auth: _FakeAuth()),
      );
      await tester.pumpAndSettle();
      await prepareAndGoOffline(tester);
      await _scan(tester, camera, 'offline.token.A');

      // _FakeApi throws when no reconcile response was primed.
      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reconcile failed'), findsOneWidget);
      expect(find.textContaining('OFFLINE – 1 scans queued'), findsOneWidget);
      expect(find.byType(ConflictListScreen), findsNothing);
    });
  });
}
