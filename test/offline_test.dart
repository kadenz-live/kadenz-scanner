import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/models/queued_scan.dart';
import 'package:kadenz_scanner/models/reconcile_result.dart';
import 'package:kadenz_scanner/services/manifest_verifier.dart';
import 'package:kadenz_scanner/services/offline_store.dart';
import 'package:kadenz_scanner/services/offline_validator.dart';

import 'support/manifest_fixtures.dart';

OfflineManifest manifestWith(
  List<ManifestEntry> entries, {
  DateTime? generatedAt,
  DateTime? validUntil,
}) =>
    OfflineManifest(
      eventId: 'evt-1',
      eventTitle: 'Concert',
      generatedAt: generatedAt ?? DateTime.utc(2030, 1, 1, 18),
      entries: entries,
      validUntil: validUntil,
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

  // kadenz#1778 — server-side valid_until is authoritative for the hard gate.
  //
  // Authority-order guards: each direction below FAILS if the implementation
  // inverts the order (fallback-first), ANDs, or ORs the constant with the
  // server deadline. Safety rationale on [OfflineManifest.validUntil]: an
  // expired manifest must NEVER admit — refusing fails safe (operator goes
  // online), admitting a revoked ticket is unrecoverable at the door.
  group('OfflineManifest valid_until authority (kadenz#1778)', () {
    final gen = DateTime.utc(2030, 6, 1, 20);

    test('server-expired beats constant-fresh: young manifest, past valid_until is hard-stale', () {
      // Age 5 min — far inside the 12h constant. Server says expired.
      // Would FAIL under fallback-first / AND semantics (constant-fresh wins).
      final m = manifestWith(
        [entryFor('A.sig', id: 't1')],
        generatedAt: gen,
        validUntil: gen.add(const Duration(minutes: 1)),
      );
      expect(m.isStaleHard(gen.add(const Duration(minutes: 5))), true);
    });

    test('server-fresh beats constant-expired: old manifest, future valid_until is not hard-stale', () {
      // Age 24h — far past the 12h constant. Server extended the window
      // (it knows event timing, e.g. multi-day events).
      // Would FAIL under OR / min(server, constant) semantics.
      final m = manifestWith(
        [entryFor('A.sig', id: 't1')],
        generatedAt: gen,
        validUntil: gen.add(const Duration(hours: 36)),
      );
      expect(m.isStaleHard(gen.add(const Duration(hours: 24))), false);
    });

    test('the expiry instant itself is already stale (never admit at valid_until)', () {
      final deadline = gen.add(const Duration(hours: 3));
      final m = manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen, validUntil: deadline);
      expect(m.isStaleHard(deadline.subtract(const Duration(seconds: 1))), false);
      expect(m.isStaleHard(deadline), true);
    });

    test('absent valid_until keeps the 12h constant fallback (pre-#1778 server)', () {
      final m = manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen);
      expect(m.validUntil, isNull);
      expect(m.isStaleHard(gen.add(OfflineManifest.hardStaleThreshold - const Duration(minutes: 1))), false);
      expect(m.isStaleHard(gen.add(OfflineManifest.hardStaleThreshold)), true);
    });

    test('validator refuses to admit an otherwise-valid ticket once the server deadline passed', () {
      // End-to-end never-admit guard: active ticket, young manifest, but the
      // server deadline has passed → forceOnline, not admitted.
      final v = OfflineValidator(
        manifestWith(
          [entryFor('A.sig', id: 't1')],
          generatedAt: gen,
          validUntil: gen.add(const Duration(minutes: 1)),
        ),
        clock: () => gen.add(const Duration(minutes: 5)),
      );
      final outcome = v.validate('A.sig');
      expect(outcome.accepted, false);
      expect(outcome.forceOnline, true);
      expect(outcome.result.status, 'manifest_stale');
    });

    test('validator admits past the 12h constant while the server deadline holds', () {
      final v = OfflineValidator(
        manifestWith(
          [entryFor('A.sig', id: 't1')],
          generatedAt: gen,
          validUntil: gen.add(const Duration(hours: 36)),
        ),
        clock: () => gen.add(const Duration(hours: 24)),
      );
      expect(v.validate('A.sig').accepted, true);
    });

    test('fromJson parses valid_until and tolerates its absence', () {
      final withField = OfflineManifest.fromJson({
        'event_id': 'evt-1',
        'generated_at': '2030-06-01T20:00:00Z',
        'valid_until': '2030-06-02T08:00:00Z',
        'tickets': <Map<String, dynamic>>[],
      });
      expect(withField.validUntil, DateTime.utc(2030, 6, 2, 8));

      final withoutField = OfflineManifest.fromJson({
        'event_id': 'evt-1',
        'generated_at': '2030-06-01T20:00:00Z',
        'tickets': <Map<String, dynamic>>[],
      });
      expect(withoutField.validUntil, isNull);
    });

    test('valid_until survives the JSON round-trip (offline-store persistence)', () {
      // Dropping the field on persist would demote a server-expired manifest
      // to the 12h fallback after an app relaunch — the unsafe direction.
      final deadline = gen.add(const Duration(hours: 3));
      final m = manifestWith([entryFor('A.sig', id: 't1')], generatedAt: gen, validUntil: deadline);
      final back = OfflineManifest.fromJson(m.toJson());
      expect(back.validUntil, isNotNull);
      expect(back.validUntil!.toUtc(), deadline);
      // And a null deadline stays null (no accidental fabrication).
      final nullBack = OfflineManifest.fromJson(manifestWith([]).toJson());
      expect(nullBack.validUntil, isNull);
    });

    test('valid_until survives OfflineStore save/load', () async {
      // kadenz#1823: the store now round-trips the wire document verbatim, so
      // "does valid_until survive persistence" is asked of the same bytes the
      // signature covers. Dropping it on persist would silently demote a
      // server-expired manifest to the 12h fallback after a relaunch.
      final store = OfflineStore(InMemoryKeyValueStore());
      final fixtures = await ManifestFixtures.create();
      final verifier = ManifestVerifier(publicKeys: fixtures.pinnedKeys);
      final raw = await fixtures.signed();

      await store.saveRawManifest('evt-1', raw);
      final loaded = await verifier.verify(
        (await store.loadRawManifest('evt-1'))!,
        hasSeenSignedManifest: true,
      );

      expect(loaded.verified, isTrue);
      expect(loaded.manifest!.validUntil, DateTime.utc(2030, 1, 2, 6));
    });
  });

  group('OfflineStore', () {
    late OfflineStore store;

    setUp(() => store = OfflineStore(InMemoryKeyValueStore()));

    test('saves and loads a manifest document by event id', () async {
      final raw = ManifestFixtures.unsigned();
      await store.saveRawManifest('evt-1', raw);

      expect(await store.loadRawManifest('evt-1'), raw);
      expect(await store.loadRawManifest('other'), isNull);
    });

    test('stores the wire document byte for byte, not a re-serialised object', () async {
      // Re-serialising would drop the signature envelope and any field this
      // build does not know about, so the stored copy could never be verified
      // again. Load and fetch have to run the identical check.
      final fixtures = await ManifestFixtures.create();
      final raw = await fixtures.signed();

      await store.saveRawManifest('evt-1', raw);

      expect(await store.loadRawManifest('evt-1'), raw);
    });

    test('reads a pre-#1823 record written by an older build', () async {
      // Upgrade path: the old build persisted the bare manifest object. It must
      // still load, or an app update would brick a door that was already
      // prepared for offline.
      final legacy = ManifestFixtures.unsigned();
      final kv = InMemoryKeyValueStore();
      await kv.write('offline_manifest_evt-1', legacy);

      final legacyStore = OfflineStore(kv);
      final loaded = await legacyStore.loadRawManifest('evt-1');

      expect(loaded, legacy);
      final verified = await ManifestVerifier(publicKeys: const {})
          .verify(loaded!, hasSeenSignedManifest: false);
      expect(verified.accepted, isTrue, reason: 'a legacy record must still be usable during rollout');
      expect(verified.verified, isFalse);
    });

    test('the signed-manifest ratchet starts open and only ever closes', () async {
      expect(await store.hasSeenSignedManifest(), isFalse);

      await store.markSignedManifestSeen();

      expect(await store.hasSeenSignedManifest(), isTrue);
    });

    test('the ratchet is not scoped to one event', () async {
      // It is a statement about the server, not about a door. Per-event scoping
      // would reopen the downgrade window on every new event.
      await store.markSignedManifestSeen();
      await store.saveRawManifest('evt-2', ManifestFixtures.unsigned());

      expect(await store.hasSeenSignedManifest(), isTrue);
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
      final r = ReconcileResult.fromJson({'accepted_count': 5, 'conflicts': <Map<String, dynamic>>[]});
      expect(r.hasConflicts, false);
      expect(r.acceptedCount, 5);
    });
  });
}
