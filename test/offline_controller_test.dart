import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/models/queued_scan.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/services/api_service.dart';
import 'package:kadenz_scanner/services/auth_service.dart';
import 'package:kadenz_scanner/services/offline_controller.dart';
import 'package:kadenz_scanner/services/offline_store.dart';

/// A fake API that serves a canned manifest and records reconcile calls,
/// so the controller can be driven without a network or platform channel.
class FakeApi extends ApiService {
  FakeApi(this.manifestData) : super(AuthService());

  final OfflineManifest manifestData;
  List<QueuedScan>? reconciledWith;
  ReconcileResult reconcileResponse =
      const ReconcileResult(acceptedCount: 0, conflicts: []);
  bool shouldThrowOnReconcile = false;

  @override
  Future<OfflineManifest> manifest(String eventId) async => manifestData;

  @override
  Future<ReconcileResult> reconcile(String eventId, List<QueuedScan> scans) async {
    if (shouldThrowOnReconcile) throw Exception('simulated network failure');
    reconciledWith = scans;
    return reconcileResponse;
  }
}

OfflineManifest sampleManifest() => OfflineManifest(
      eventId: 'evt-1',
      eventTitle: 'Concert',
      generatedAt: DateTime.utc(2030, 1, 1, 18),
      entries: [
        ManifestEntry(id: 't1', digest: OfflineManifest.digestOf('A.sig'), status: 'active'),
        ManifestEntry(id: 't2', digest: OfflineManifest.digestOf('B.sig'), status: 'active'),
      ],
    );

OfflineManifest threeTicketManifest() => OfflineManifest(
      eventId: 'evt-1',
      eventTitle: 'Concert',
      generatedAt: DateTime.utc(2030, 1, 1, 18),
      entries: [
        ManifestEntry(id: 't1', digest: OfflineManifest.digestOf('A.sig'), status: 'active'),
        ManifestEntry(id: 't2', digest: OfflineManifest.digestOf('B.sig'), status: 'active'),
        ManifestEntry(id: 't3', digest: OfflineManifest.digestOf('C.sig'), status: 'active'),
      ],
    );

OfflineController buildController(FakeApi api, OfflineStore store) =>
    OfflineController(api: api, eventId: 'evt-1', deviceId: 'door-a', store: store);

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
      expect(await store.loadManifest('evt-1'), isNotNull);
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
      await store.saveManifest(sampleManifest());
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
}
