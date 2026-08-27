import 'package:flutter/foundation.dart';

import '../models/offline_manifest.dart';
import '../models/queued_scan.dart';
import '../models/reconcile_result.dart';
import '../models/validation_result.dart';
import 'api_service.dart';
import 'manifest_verifier.dart';
import 'offline_store.dart';
import 'offline_validator.dart';

/// Raised when a manifest was refused (kadenz#1823, ADR-0055).
///
/// Carries the reason so the UI can say which of the three refusals happened —
/// "the document was edited" and "this build does not hold the signing key"
/// need very different operator responses.
class ManifestRejectedException implements Exception {
  const ManifestRejectedException(this.reason);

  final ManifestRejection reason;

  @override
  String toString() => 'ManifestRejectedException(${reason.name})';
}

/// Coordinates offline preparation, offline scanning, and reconcile for one
/// event. UI listens to this; all storage + validation goes through it.
class OfflineController extends ChangeNotifier {
  OfflineController({
    required this.api,
    required this.eventId,
    required this.deviceId,
    OfflineStore? store,
    ManifestVerifier? verifier,
  })  : _store = store ?? OfflineStore(PrefsKeyValueStore()),
        _verifier = verifier ?? ManifestVerifier();

  final ApiService api;
  final String eventId;
  final String deviceId;
  final OfflineStore _store;
  final ManifestVerifier _verifier;

  OfflineManifest? _manifest;
  OfflineValidator? _validator;
  bool _offline = false;
  int _queued = 0;
  bool _busy = false;
  ManifestRejection? _lastRejection;

  bool get isOffline => _offline;
  bool get isReady => _manifest != null;
  bool get isBusy => _busy;
  int get queuedCount => _queued;
  DateTime? get manifestGeneratedAt => _manifest?.generatedAt;
  int get manifestTicketCount => _manifest?.ticketCount ?? 0;

  /// Whether the manifest currently in hand was verified (kadenz#1823).
  bool get isManifestVerified => _manifest?.isSigned ?? false;

  /// Why the last manifest was refused, if one was. Cleared on the next
  /// successful sync or restore.
  ManifestRejection? get lastRejection => _lastRejection;

  /// Restore a previously synced manifest + queue (e.g. on screen open).
  ///
  /// The stored document goes through the same verification a freshly fetched
  /// one does. A manifest that was edited in local storage after it was synced
  /// is refused here, which is the point: storage is not a trust boundary.
  Future<void> restore() async {
    final raw = await _store.loadRawManifest(eventId);
    if (raw == null) {
      notifyListeners();
      return;
    }

    final verification = await _verifier.verify(
      raw,
      hasSeenSignedManifest: await _store.hasSeenSignedManifest(),
    );
    if (!verification.accepted) {
      // Refuse to load it. With no validator, offline validation returns
      // `no_manifest` and admits nobody — the safe direction.
      _manifest = null;
      _validator = null;
      _lastRejection = verification.rejection;
      notifyListeners();
      return;
    }

    _lastRejection = null;
    _manifest = verification.manifest;
    final scanned = await _store.queuedTicketIds(eventId);
    _validator = OfflineValidator(_manifest!, alreadyScanned: scanned);
    _queued = (await _store.loadQueue(eventId)).length;
    notifyListeners();
  }

  /// "Offline-Modus vorbereiten" — pull, verify and persist the manifest.
  ///
  /// **Last-known-good is preferred over nothing** (ADR-0055 §E). A manifest
  /// that does not verify is neither stored nor installed, and — critically —
  /// does not evict the one already in hand. A door that was prepared stays
  /// prepared until its manifest legitimately expires; the operator is told the
  /// sync was refused via [ManifestRejectedException].
  ///
  /// The alternative, clearing on rejection, would hand anyone who can put one
  /// bad response in front of the device the ability to shut the door
  /// immediately. That is a worse primitive than the stale-manifest residual it
  /// would close.
  Future<void> prepareOffline() async {
    _setBusy(true);
    try {
      final raw = await api.manifestDocument(eventId);
      final verification = await _verifier.verify(
        raw,
        hasSeenSignedManifest: await _store.hasSeenSignedManifest(),
      );

      if (!verification.accepted) {
        _lastRejection = verification.rejection;
        // Thrown before anything is written or replaced: whatever manifest and
        // validator were in hand are still in hand.
        throw ManifestRejectedException(verification.rejection!);
      }

      // Close the ratchet before storing, so a crash between the two leaves the
      // device stricter rather than more permissive.
      if (verification.verified) await _store.markSignedManifestSeen();

      await _store.saveRawManifest(eventId, raw);
      _lastRejection = null;
      _manifest = verification.manifest;
      final scanned = await _store.queuedTicketIds(eventId);
      _validator = OfflineValidator(_manifest!, alreadyScanned: scanned);
      _queued = (await _store.loadQueue(eventId)).length;
    } finally {
      _setBusy(false);
    }
  }

  void enterOfflineMode() {
    _offline = true;
    notifyListeners();
  }

  void exitOfflineMode() {
    _offline = false;
    notifyListeners();
  }

  /// Validate a scan offline and queue it on acceptance.
  /// Caller must ensure [isReady] (a manifest is loaded).
  Future<ValidationResult> validateOffline(String qrToken) async {
    final validator = _validator;
    if (validator == null) {
      return ValidationResult(
        ok: false,
        status: 'no_manifest',
        message: 'Kein Offline-Manifest geladen',
      );
    }
    final outcome = validator.validate(qrToken);
    if (outcome.accepted) {
      await _store.enqueue(
        eventId,
        QueuedScan(ticketId: outcome.acceptedTicketId!, scannedAt: DateTime.now(), deviceId: deviceId),
      );
      _queued += 1;
      notifyListeners();
    }
    return outcome.result;
  }

  /// Push the queue to the server. On success the local queue is cleared and
  /// the conflict list is returned for review.
  Future<ReconcileResult> reconcile() async {
    _setBusy(true);
    try {
      final queue = await _store.loadQueue(eventId);
      final result = await api.reconcile(eventId, queue);
      await _store.clearQueue(eventId);
      _queued = 0;
      _offline = false;
      return result;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
