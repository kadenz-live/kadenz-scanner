import 'package:flutter/foundation.dart';

import '../models/offline_manifest.dart';
import '../models/queued_scan.dart';
import '../models/reconcile_result.dart';
import '../models/validation_result.dart';
import 'api_service.dart';
import 'offline_store.dart';
import 'offline_validator.dart';

/// Coordinates offline preparation, offline scanning, and reconcile for one
/// event. UI listens to this; all storage + validation goes through it.
class OfflineController extends ChangeNotifier {
  OfflineController({
    required this.api,
    required this.eventId,
    required this.deviceId,
    OfflineStore? store,
  }) : _store = store ?? OfflineStore(PrefsKeyValueStore());

  final ApiService api;
  final String eventId;
  final String deviceId;
  final OfflineStore _store;

  OfflineManifest? _manifest;
  OfflineValidator? _validator;
  bool _offline = false;
  int _queued = 0;
  bool _busy = false;

  bool get isOffline => _offline;
  bool get isReady => _manifest != null;
  bool get isBusy => _busy;
  int get queuedCount => _queued;
  DateTime? get manifestGeneratedAt => _manifest?.generatedAt;
  int get manifestTicketCount => _manifest?.ticketCount ?? 0;

  /// Restore a previously synced manifest + queue (e.g. on screen open).
  Future<void> restore() async {
    _manifest = await _store.loadManifest(eventId);
    if (_manifest != null) {
      final scanned = await _store.queuedTicketIds(eventId);
      _validator = OfflineValidator(_manifest!, alreadyScanned: scanned);
      _queued = (await _store.loadQueue(eventId)).length;
    }
    notifyListeners();
  }

  /// "Offline-Modus vorbereiten" — pull and persist the manifest.
  Future<void> prepareOffline() async {
    _setBusy(true);
    try {
      final manifest = await api.manifest(eventId);
      await _store.saveManifest(manifest);
      _manifest = manifest;
      final scanned = await _store.queuedTicketIds(eventId);
      _validator = OfflineValidator(manifest, alreadyScanned: scanned);
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
