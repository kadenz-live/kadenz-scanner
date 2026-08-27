import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/queued_scan.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/services/api_service.dart';
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:kadenz_scanner/services/manifest_verifier.dart';
import 'package:kadenz_scanner/services/offline_controller.dart';
import 'package:kadenz_scanner/services/offline_store.dart';

import 'support/manifest_fixtures.dart';

/// A fake API that serves a canned manifest **document** and records reconcile
/// calls, so the controller can be driven without a network or platform
/// channel.
///
/// It serves the raw wire string rather than a parsed object (kadenz#1823): the
/// controller's job now includes verifying those bytes, and a fake that handed
/// back a pre-parsed manifest would skip exactly the code under test.
class FakeApi extends ApiService {
  FakeApi(this.manifestDocumentData) : super(AuthService());

  String manifestDocumentData;
  List<QueuedScan>? reconciledWith;
  ReconcileResult reconcileResponse =
      const ReconcileResult(acceptedCount: 0, conflicts: []);
  bool shouldThrowOnReconcile = false;

  @override
  Future<String> manifestDocument(String eventId) async => manifestDocumentData;

  @override
  Future<ReconcileResult> reconcile(String eventId, List<QueuedScan> scans) async {
    if (shouldThrowOnReconcile) throw Exception('simulated network failure');
    reconciledWith = scans;
    return reconcileResponse;
  }
}

Map<String, dynamic> manifestDoc(List<String> tokens) => ManifestFixtures.document(
      validUntil: '2030-01-02T06:00:00.000Z',
      tickets: [
        for (var i = 0; i < tokens.length; i++)
          {
            'id': 't${i + 1}',
            'digest': ManifestFixtures.digestOf(tokens[i]),
            'status': 'active',
          },
      ],
    );

String sampleManifest() => ManifestFixtures.unsigned(manifestDoc(['A.sig', 'B.sig']));

String threeTicketManifest() =>
    ManifestFixtures.unsigned(manifestDoc(['A.sig', 'B.sig', 'C.sig']));

OfflineController buildController(FakeApi api, OfflineStore store, {ManifestVerifier? verifier}) =>
    OfflineController(
      api: api,
      eventId: 'evt-1',
      deviceId: 'door-a',
      store: store,
      verifier: verifier ?? ManifestVerifier(publicKeys: const {}),
    );

void main() {
  group('OfflineController', () {
    late FakeApi api;
    late OfflineStore store;
    late OfflineController controller;

    setUp(() {
      api = FakeApi(sampleManifest());
      store = OfflineStore(InMemoryKeyValueStore());
      controller = buildController(api, store);
    });

    test('prepareOffline loads and persists the manifest', () async {
      await controller.prepareOffline();
      expect(controller.isReady, true);
      expect(controller.manifestTicketCount, 2);
      // Persisted for relaunch.
      expect(await store.loadRawManifest('evt-1'), isNotNull);
    });

    test('offline scan accepts, queues, and bumps the counter', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();

      final r = await controller.validateOffline('A.sig');
      expect(r.ok, true);
      expect(controller.queuedCount, 1);
      expect((await store.loadQueue('evt-1')).single.ticketId, 't1');
    });

    test('offline double-scan of the same ticket is rejected', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();

      await controller.validateOffline('A.sig');
      final second = await controller.validateOffline('A.sig');
      expect(second.ok, false);
      expect(second.status, 'already_used');
      expect(controller.queuedCount, 1);
    });

    test('reconcile pushes the queue, clears it, and exits offline mode', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();
      await controller.validateOffline('A.sig');
      await controller.validateOffline('B.sig');

      api.reconcileResponse = const ReconcileResult(acceptedCount: 2, conflicts: []);
      final result = await controller.reconcile();

      expect(result.acceptedCount, 2);
      expect(api.reconciledWith!.length, 2);
      expect(controller.queuedCount, 0);
      expect(controller.isOffline, false);
      expect(await store.loadQueue('evt-1'), isEmpty);
    });

    test('restore rebuilds the dedupe set from a persisted queue', () async {
      await store.saveRawManifest('evt-1', sampleManifest());
      await store.enqueue('evt-1',
          QueuedScan(ticketId: 't1', scannedAt: DateTime.utc(2030, 1, 1, 21), deviceId: 'door-a'));

      await controller.restore();
      controller.enterOfflineMode();

      // t1 was already queued before relaunch — must be rejected now.
      final r = await controller.validateOffline('A.sig');
      expect(r.ok, false);
      expect(r.status, 'already_used');
      expect(controller.queuedCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Offline-mode regression scenarios (ADR-0018)
  // ---------------------------------------------------------------------------

  group('OfflineController — reconnect and sync scenarios', () {
    late FakeApi api;
    late OfflineStore store;
    late OfflineController controller;

    setUp(() {
      api = FakeApi(threeTicketManifest());
      store = OfflineStore(InMemoryKeyValueStore());
      controller = buildController(api, store);
    });

    test('3 offline scans sync all 3 to backend on reconnect', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();

      expect((await controller.validateOffline('A.sig')).ok, true);
      expect((await controller.validateOffline('B.sig')).ok, true);
      expect((await controller.validateOffline('C.sig')).ok, true);
      expect(controller.queuedCount, 3);

      api.reconcileResponse = const ReconcileResult(acceptedCount: 3, conflicts: []);
      final result = await controller.reconcile();

      expect(result.acceptedCount, 3);
      expect(result.hasConflicts, false);
      expect(api.reconciledWith!.length, 3);
      expect(api.reconciledWith!.map((s) => s.ticketId), containsAll(['t1', 't2', 't3']));
      expect(controller.queuedCount, 0);
      expect(controller.isOffline, false);
      expect(await store.loadQueue('evt-1'), isEmpty);
    });

    test('double offline scan of same ticket sends only 1 entry to reconcile', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();

      final first = await controller.validateOffline('A.sig');
      final second = await controller.validateOffline('A.sig');

      expect(first.ok, true);
      expect(second.ok, false);
      expect(second.status, 'already_used');
      expect(controller.queuedCount, 1);

      // Only 1 scan item must reach the server — not 2.
      api.reconcileResponse = const ReconcileResult(acceptedCount: 1, conflicts: []);
      final result = await controller.reconcile();

      expect(api.reconciledWith!.length, 1);
      expect(api.reconciledWith!.single.ticketId, 't1');
      expect(result.acceptedCount, 1);
      expect(controller.queuedCount, 0);
    });

    test(
        'ticket active in manifest but expired: reconcile flags it as not_eligible conflict',
        () async {
      // Manifest lists the ticket as active — it was active when the manifest was
      // synced, but the event has since ended. The offline validator accepts it
      // (HMAC matches, status is active); the server catches the expiry during
      // reconcile and returns a not_eligible conflict.
      await controller.prepareOffline();
      controller.enterOfflineMode();

      final r = await controller.validateOffline('A.sig');
      expect(r.ok, true);
      expect(controller.queuedCount, 1);

      api.reconcileResponse = const ReconcileResult(
        acceptedCount: 0,
        conflicts: [
          ReconcileConflict(ticketId: 't1', reason: 'not_eligible'),
        ],
      );
      final result = await controller.reconcile();

      expect(result.acceptedCount, 0);
      expect(result.hasConflicts, true);
      expect(result.conflicts.single.ticketId, 't1');
      expect(result.conflicts.single.reason, 'not_eligible');
      // Queue is cleared regardless — server is source of truth.
      expect(controller.queuedCount, 0);
      expect(await store.loadQueue('evt-1'), isEmpty);
    });

    test('reconcile failure preserves queue; retry on reconnect syncs all scans', () async {
      await controller.prepareOffline();
      controller.enterOfflineMode();

      await controller.validateOffline('A.sig');
      await controller.validateOffline('B.sig');
      expect(controller.queuedCount, 2);

      // Simulate network drop mid-reconcile.
      api.shouldThrowOnReconcile = true;
      await expectLater(controller.reconcile(), throwsException);

      // Queue and offline state must be intact after the failure.
      expect(controller.queuedCount, 2);
      expect(controller.isOffline, true);
      expect(await store.loadQueue('evt-1'), hasLength(2));

      // Network reconnects — retry sends all queued scans.
      api.shouldThrowOnReconcile = false;
      api.reconcileResponse = const ReconcileResult(acceptedCount: 2, conflicts: []);
      final result = await controller.reconcile();

      expect(result.acceptedCount, 2);
      expect(api.reconciledWith!.length, 2);
      expect(controller.queuedCount, 0);
      expect(controller.isOffline, false);
    });
  });

  // ---------------------------------------------------------------------------
  // kadenz#1823 — manifest signature, last-known-good, and the rollout ratchet
  // ---------------------------------------------------------------------------

  group('OfflineController — manifest verification', () {
    late ManifestFixtures fixtures;
    late OfflineStore store;

    Future<OfflineController> controllerServing(String document, {ManifestVerifier? verifier}) async {
      final api = FakeApi(document);
      return buildController(api, store, verifier: verifier ?? ManifestVerifier(publicKeys: fixtures.pinnedKeys));
    }

    /// A signed manifest whose digests match the tokens the other tests scan.
    Future<String> signedManifest() => fixtures.signed(doc: manifestDoc(['A.sig', 'B.sig']));

    setUp(() async {
      fixtures = await ManifestFixtures.create();
      store = OfflineStore(InMemoryKeyValueStore());
    });

    test('a signed manifest is accepted, persisted and marked verified', () async {
      final controller = await controllerServing(await signedManifest());

      await controller.prepareOffline();

      expect(controller.isReady, isTrue);
      expect(controller.isManifestVerified, isTrue);
      expect(controller.lastRejection, isNull);
      expect(await store.hasSeenSignedManifest(), isTrue);
    });

    test('an unsigned manifest is accepted during rollout but not marked verified', () async {
      final controller = await controllerServing(ManifestFixtures.unsigned(manifestDoc(['A.sig'])));

      await controller.prepareOffline();

      expect(controller.isReady, isTrue);
      expect(controller.isManifestVerified, isFalse);
      expect(await store.hasSeenSignedManifest(), isFalse,
          reason: 'the ratchet must not close on something that was never verified');
    });

    test('a tampered manifest is refused and does not evict the last known good one', () async {
      // The property the whole design turns on: a scanner already holding a
      // valid manifest is not bricked by a bad one arriving.
      final controller = await controllerServing(await signedManifest());
      await controller.prepareOffline();
      final storedBefore = await store.loadRawManifest('evt-1');
      controller.enterOfflineMode();

      final tampered = ManifestFixtures.tamperPayload(
        await signedManifest(),
        (doc) => {...doc, 'valid_until': '2999-01-01T00:00:00.000Z'},
      );
      final poisoned = await controllerServing(tampered);
      // Same store, so this is the same device receiving a second manifest.
      await expectLater(
        poisoned.prepareOffline(),
        throwsA(isA<ManifestRejectedException>()
            .having((e) => e.reason, 'reason', ManifestRejection.signatureInvalid)),
      );

      expect(await store.loadRawManifest('evt-1'), storedBefore,
          reason: 'the stored manifest must survive a refused sync');
      // And the door that was already prepared is still admitting.
      expect(controller.isReady, isTrue);
      final verdict = await controller.validateOffline('A.sig');
      expect(verdict.ok, isTrue);
    });

    test('a refused sync leaves the in-hand manifest and validator untouched', () async {
      final controller = await controllerServing(await signedManifest());
      await controller.prepareOffline();
      final ticketCount = controller.manifestTicketCount;

      // Now the same controller is asked to sync a document it cannot accept.
      final stripped = ManifestFixtures.stripSignature(await signedManifest());
      final second = await controllerServing(stripped);
      await store.markSignedManifestSeen();
      await expectLater(second.prepareOffline(), throwsA(isA<ManifestRejectedException>()));

      expect(controller.isReady, isTrue);
      expect(controller.manifestTicketCount, ticketCount);
    });

    test('once a signed manifest has been seen, an unsigned one is refused', () async {
      final signedController = await controllerServing(await signedManifest());
      await signedController.prepareOffline();

      final downgrade = await controllerServing(ManifestFixtures.unsigned(manifestDoc(['A.sig'])));

      await expectLater(
        downgrade.prepareOffline(),
        throwsA(isA<ManifestRejectedException>()
            .having((e) => e.reason, 'reason', ManifestRejection.signatureMissing)),
      );
    });

    test('restore re-verifies the stored document rather than trusting storage', () async {
      // Storage is not a trust boundary: the manifest sits in SharedPreferences
      // next to the offline queue on a device the door staff hold.
      final kv = InMemoryKeyValueStore();
      final tamperedStore = OfflineStore(kv);
      await tamperedStore.markSignedManifestSeen();
      await tamperedStore.saveRawManifest(
        'evt-1',
        ManifestFixtures.tamperPayload(
          await signedManifest(),
          (doc) => {
            ...doc,
            'tickets': [
              ...(doc['tickets'] as List),
              {'id': 'smuggled', 'digest': ManifestFixtures.digestOf('X.sig'), 'status': 'active'},
            ],
          },
        ),
      );

      final controller = OfflineController(
        api: FakeApi(await signedManifest()),
        eventId: 'evt-1',
        deviceId: 'door-a',
        store: tamperedStore,
        verifier: ManifestVerifier(publicKeys: fixtures.pinnedKeys),
      );
      await controller.restore();

      expect(controller.isReady, isFalse);
      expect(controller.lastRejection, ManifestRejection.signatureInvalid);

      // And with no validator, nothing is admitted — the safe direction.
      controller.enterOfflineMode();
      final verdict = await controller.validateOffline('X.sig');
      expect(verdict.ok, isFalse);
      expect(verdict.status, 'no_manifest');
    });

    test('restore accepts a stored signed manifest and keeps it verified', () async {
      final controller = await controllerServing(await signedManifest());
      await controller.prepareOffline();

      final relaunched = await controllerServing(await signedManifest());
      await relaunched.restore();

      expect(relaunched.isReady, isTrue);
      expect(relaunched.isManifestVerified, isTrue);
    });

    test('an upgraded app still restores a manifest persisted by the previous build', () async {
      // No ratchet yet (this device has never verified anything), and the old
      // record has no envelope. It must load, or the upgrade takes a prepared
      // door down.
      final kv = InMemoryKeyValueStore();
      await kv.write('offline_manifest_evt-1', ManifestFixtures.unsigned(manifestDoc(['A.sig'])));
      final legacyStore = OfflineStore(kv);

      final controller = OfflineController(
        api: FakeApi(ManifestFixtures.unsigned(manifestDoc(['A.sig']))),
        eventId: 'evt-1',
        deviceId: 'door-a',
        store: legacyStore,
        verifier: ManifestVerifier(publicKeys: fixtures.pinnedKeys),
      );
      await controller.restore();

      expect(controller.isReady, isTrue);
      expect(controller.isManifestVerified, isFalse);
      controller.enterOfflineMode();
      expect((await controller.validateOffline('A.sig')).ok, isTrue);
    });
  });
}
