import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/models/queued_scan.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/services/offline_store.dart';
import 'package:kadenz_scanner/services/offline_validator.dart';

OfflineManifest manifestWith(List<ManifestEntry> entries, {DateTime? generatedAt}) =>
    OfflineManifest(
      eventId: 'evt-1',
      eventTitle: 'Concert',
      generatedAt: generatedAt ?? DateTime.utc(2030, 1, 1, 18),
      entries: entries,
    );

ManifestEntry entryFor(String token, {required String id, String status = 'active'}) =>
    ManifestEntry(id: id, digest: OfflineManifest.digestOf(token), status: status);

void main() {
  group('OfflineManifest', () {
    test('digestOf is a stable SHA-256 hex of the token', () {
      final d = OfflineManifest.digestOf('TOKEN.sig');
      expect(d, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(d, OfflineManifest.digestOf('TOKEN.sig'));
      expect(d, isNot(OfflineManifest.digestOf('OTHER.sig')));
    });

    test('round-trips through JSON', () {
      final m = manifestWith([entryFor('A.sig', id: 't1')]);
      final back = OfflineManifest.fromJson(m.toJson());
      expect(back.eventId, 'evt-1');
      expect(back.entries.single.id, 't1');
      expect(back.entries.single.digest, m.entries.single.digest);
    });
  });

  group('OfflineValidator', () {
    test('accepts an active ticket and reports its id for the queue', () {
      final v = OfflineValidator(manifestWith([entryFor('A.sig', id: 't1')]));
      final outcome = v.validate('A.sig');
      expect(outcome.result.ok, true);
      expect(outcome.accepted, true);
      expect(outcome.acceptedTicketId, 't1');
    });

    test('rejects an unknown token (not in manifest)', () {
      final v = OfflineValidator(manifestWith([entryFor('A.sig', id: 't1')]));
      final outcome = v.validate('FORGED.sig');
      expect(outcome.result.ok, false);
      expect(outcome.result.status, 'not_found');
      expect(outcome.accepted, false);
    });

    test('rejects a void ticket', () {
      final v = OfflineValidator(manifestWith([entryFor('A.sig', id: 't1', status: 'void')]));
      expect(v.validate('A.sig').result.status, 'void');
    });

    test('rejects a ticket already used at sync time', () {
      final v = OfflineValidator(manifestWith([entryFor('A.sig', id: 't1', status: 'used')]));
      expect(v.validate('A.sig').result.status, 'already_used');
    });

    test('rejects a same-device double scan within the offline session', () {
      final v = OfflineValidator(manifestWith([entryFor('A.sig', id: 't1')]));
      expect(v.validate('A.sig').accepted, true);
      final second = v.validate('A.sig');
      expect(second.accepted, false);
      expect(second.result.status, 'already_used');
    });

    test('seeds dedupe from an already-scanned set (relaunch mid-window)', () {
      final v = OfflineValidator(
        manifestWith([entryFor('A.sig', id: 't1')]),
        alreadyScanned: {'t1'},
      );
      final outcome = v.validate('A.sig');
      expect(outcome.accepted, false);
      expect(outcome.result.status, 'already_used');
    });
  });

  group('OfflineValidator staleness gate', () {
    final gen = DateTime.utc(2030, 6, 1, 20);
    DateTime Function() clockAt(DateTime t) => () => t;

    test('fresh manifest admits with no stale warning', () {
      final v = OfflineValidator(
        manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen),
        clock: clockAt(gen.add(const Duration(minutes: 5))),
      );
      final outcome = v.validate('A.sig');
      expect(outcome.accepted, true);
      expect(outcome.staleWarning, false);
      expect(outcome.forceOnline, false);
    });

    test('past the soft threshold still admits but flags a stale warning', () {
      final v = OfflineValidator(
        manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen),
        clock: clockAt(gen.add(OfflineManifest.softStaleThreshold + const Duration(minutes: 1))),
      );
      final outcome = v.validate('A.sig');
      expect(outcome.accepted, true);
      expect(outcome.staleWarning, true);
      expect(outcome.forceOnline, false);
    });

    test('past the hard threshold refuses to admit and forces online', () {
      final v = OfflineValidator(
        manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen),
        clock: clockAt(gen.add(OfflineManifest.hardStaleThreshold + const Duration(minutes: 1))),
      );
      final outcome = v.validate('A.sig');
      expect(outcome.accepted, false);
      expect(outcome.forceOnline, true);
      expect(outcome.result.ok, false);
      expect(outcome.result.status, 'manifest_stale');
    });

    test('hard-stale gate fires before the digest lookup (even for a valid ticket)', () {
      // A ticket that would otherwise admit must be refused once hard-stale:
      // the manifest may pre-date a revoke/refund since the last sync.
      final v = OfflineValidator(
        manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen),
        clock: clockAt(gen.add(const Duration(days: 2))),
      );
      expect(v.validate('A.sig').forceOnline, true);
      expect(v.validate('A.sig').accepted, false);
    });

    test('isStaleSoft / isStaleHard reflect the thresholds', () {
      final m = manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen);
      expect(m.isStaleSoft(gen.add(const Duration(minutes: 1))), false);
      expect(m.isStaleSoft(gen.add(OfflineManifest.softStaleThreshold)), true);
      expect(m.isStaleHard(gen.add(OfflineManifest.softStaleThreshold)), false);
      expect(m.isStaleHard(gen.add(OfflineManifest.hardStaleThreshold)), true);
    });
  });

  group('OfflineStore', () {
    late OfflineStore store;

    setUp(() => store = OfflineStore(InMemoryKeyValueStore()));

    test('saves and loads a manifest by event id', () async {
      final m = manifestWith([entryFor('A.sig', id: 't1')]);
      await store.saveManifest(m);
      final loaded = await store.loadManifest('evt-1');
      expect(loaded, isNotNull);
      expect(loaded!.entries.single.id, 't1');
      expect(await store.loadManifest('other'), isNull);
    });

    test('enqueues scans and reports queued ticket ids', () async {
      await store.enqueue('evt-1', QueuedScan(ticketId: 't1', scannedAt: DateTime.utc(2030, 1, 1, 21), deviceId: 'd1'));
      await store.enqueue('evt-1', QueuedScan(ticketId: 't2', scannedAt: DateTime.utc(2030, 1, 1, 21, 5), deviceId: 'd1'));

      final queue = await store.loadQueue('evt-1');
      expect(queue.map((s) => s.ticketId), ['t1', 't2']);
      expect(await store.queuedTicketIds('evt-1'), {'t1', 't2'});
    });

    test('clears the queue after a successful reconcile', () async {
      await store.enqueue('evt-1', QueuedScan(ticketId: 't1', scannedAt: DateTime.utc(2030), deviceId: 'd1'));
      await store.clearQueue('evt-1');
      expect(await store.loadQueue('evt-1'), isEmpty);
    });

    test('queues are isolated per event', () async {
      await store.enqueue('evt-1', QueuedScan(ticketId: 't1', scannedAt: DateTime.utc(2030), deviceId: 'd1'));
      expect(await store.loadQueue('evt-2'), isEmpty);
    });
  });

  group('QueuedScan', () {
    test('serialises scanned_at as UTC ISO-8601', () {
      final scan = QueuedScan(ticketId: 't1', scannedAt: DateTime.utc(2030, 1, 1, 21, 2), deviceId: 'door-a');
      final json = scan.toJson();
      expect(json['ticket_id'], 't1');
      expect(json['device_id'], 'door-a');
      expect(json['scanned_at'], '2030-01-01T21:02:00.000Z');
      expect(QueuedScan.fromJson(json).ticketId, 't1');
    });
  });

  group('ReconcileResult', () {
    test('parses accepted count and conflict details', () {
      final r = ReconcileResult.fromJson({
        'accepted_count': 2,
        'conflicts': [
          {
            'ticket_id': 't9',
            'reason': 'already_used',
            'device_id': 'door-b',
            'already_checked_in_by': 'offline:scan@x:door-a',
            'already_checked_in_at': '2030-01-01T21:02:00Z',
          }
        ],
      });
      expect(r.acceptedCount, 2);
      expect(r.hasConflicts, true);
      expect(r.conflictCount, 1);
      final c = r.conflicts.single;
      expect(c.ticketId, 't9');
      expect(c.reason, 'already_used');
      expect(c.deviceId, 'door-b');
      expect(c.alreadyCheckedInBy, contains('door-a'));
    });

    test('handles an empty conflict list', () {
      final r = ReconcileResult.fromJson({'accepted_count': 5, 'conflicts': []});
      expect(r.hasConflicts, false);
      expect(r.acceptedCount, 5);
    });
  });
}
