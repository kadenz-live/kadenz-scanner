import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/queued_scan.dart';

/// Minimal key-value abstraction so the offline store is unit-testable
/// without the SharedPreferences plugin (which needs a platform channel).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// SharedPreferences-backed implementation (follows the app's existing
/// storage convention: secure_storage for credentials, prefs for app data).
class PrefsKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// In-memory store for tests.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Persists the synced manifest and the offline scan queue per event.
///
/// Storage is namespaced by event id so multiple events can be prepared and
/// reconciled independently.
class OfflineStore {
  OfflineStore(this._kv);
  final KeyValueStore _kv;

  String _manifestKey(String eventId) => 'offline_manifest_$eventId';
  String _queueKey(String eventId) => 'offline_queue_$eventId';

  /// Set once this device has ever verified a signed manifest (kadenz#1823).
  ///
  /// Deliberately **not** namespaced by event: it is a statement about the
  /// server this device talks to, not about one door. Namespacing it per event
  /// would reopen the downgrade window on every new event.
  static const String _signedSeenKey = 'manifest_signature_seen';

  /// Storage schema of a manifest record. Records without it are pre-#1823 and
  /// hold the parsed manifest directly.
  static const String _schemaKey = 'schema';
  static const int _schemaVersion = 2;

  /// Persist the manifest as the **exact bytes the server sent**.
  ///
  /// Not `manifest.toJson()`: re-serialising a parsed object would drop the
  /// signature envelope and every field this build does not know about, so the
  /// stored copy could never be verified again. Storing the wire document means
  /// load and fetch run the identical verification, which is the only way "the
  /// manifest on disk was not edited" can be a real claim rather than a
  /// re-assertion of whatever was parsed at sync time.
  Future<void> saveRawManifest(String eventId, String rawDocument) =>
      _kv.write(_manifestKey(eventId), jsonEncode({_schemaKey: _schemaVersion, 'body': rawDocument}));

  /// The stored wire document, or null when nothing is stored.
  ///
  /// A pre-#1823 record — written by an older build as a bare manifest object —
  /// is handed back as-is. It has no signature, so it lands on the unsigned
  /// branch of the verifier and is tolerated only while the ratchet is open.
  /// That is what stops an app upgrade from bricking a prepared door.
  Future<String?> loadRawManifest(String eventId) async {
    final raw = await _kv.read(_manifestKey(eventId));
    if (raw == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return raw;
    }
    if (decoded is Map<String, dynamic> && decoded[_schemaKey] == _schemaVersion) {
      final body = decoded['body'];
      return body is String ? body : null;
    }
    return raw;
  }

  /// The one-way ratchet (ADR-0055 §C). Once true, an unverifiable manifest is
  /// never accepted again on this device.
  Future<bool> hasSeenSignedManifest() async =>
      (await _kv.read(_signedSeenKey)) == 'true';

  Future<void> markSignedManifestSeen() => _kv.write(_signedSeenKey, 'true');

  Future<List<QueuedScan>> loadQueue(String eventId) async {
    final raw = await _kv.read(_queueKey(eventId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(QueuedScan.fromJson)
        .toList();
  }

  Future<void> enqueue(String eventId, QueuedScan scan) async {
    final queue = await loadQueue(eventId);
    queue.add(scan);
    await _saveQueue(eventId, queue);
  }

  Future<void> clearQueue(String eventId) => _kv.delete(_queueKey(eventId));

  Future<void> _saveQueue(String eventId, List<QueuedScan> queue) =>
      _kv.write(_queueKey(eventId), jsonEncode(queue.map((s) => s.toJson()).toList()));

  /// Ticket ids already queued offline — seeds the validator's dedupe set so
  /// a relaunch mid-window keeps rejecting same-device double scans.
  Future<Set<String>> queuedTicketIds(String eventId) async =>
      (await loadQueue(eventId)).map((s) => s.ticketId).toSet();
}
