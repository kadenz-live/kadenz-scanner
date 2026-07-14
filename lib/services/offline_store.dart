import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_manifest.dart';
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

  Future<void> saveManifest(OfflineManifest manifest) =>
      _kv.write(_manifestKey(manifest.eventId), jsonEncode(manifest.toJson()));

  Future<OfflineManifest?> loadManifest(String eventId) async {
    final raw = await _kv.read(_manifestKey(eventId));
    if (raw == null) return null;
    return OfflineManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

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
