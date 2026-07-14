import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A single ticket entry in an offline manifest: the ticket id, a SHA-256
/// digest of its signed QR token, and a collapsed status.
class ManifestEntry {
  const ManifestEntry({
    required this.id,
    required this.digest,
    required this.status,
  });

  final String id;
  final String digest;
  final String status; // active | used | void

  factory ManifestEntry.fromJson(Map<String, dynamic> j) => ManifestEntry(
        id: j['id'] as String,
        digest: j['digest'] as String,
        status: j['status'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'digest': digest, 'status': status};
}

/// The offline-validation manifest for one event.
///
/// The HMAC signing secret never reaches the device. Validation works by
/// hashing the scanned QR token (SHA-256) and matching it against the
/// precomputed [ManifestEntry.digest] — a forged token cannot produce a
/// matching digest without the server-side secret.
class OfflineManifest {
  const OfflineManifest({
    required this.eventId,
    required this.eventTitle,
    required this.generatedAt,
    required this.entries,
  });

  final String eventId;
  final String eventTitle;
  final DateTime generatedAt;
  final List<ManifestEntry> entries;

  /// Soft threshold: past this age the operator sees a prominent
  /// stale-manifest warning but scans still go through. Re-sync recommended.
  static const Duration softStaleThreshold = Duration(hours: 2);

  /// Hard threshold: past this age offline validation refuses to admit any
  /// ticket. A manifest this old may not reflect revoke/refund events since
  /// the last sync, so we force the operator back online rather than risk
  /// admitting a ticket that was revoked after the manifest was generated.
  ///
  /// This is a conservative client-side constant applied to [generatedAt]
  /// until the server emits an explicit `valid_until` — see the follow-up
  /// note in the PR. When a server-side `valid_until` lands it should
  /// override this constant.
  static const Duration hardStaleThreshold = Duration(hours: 12);

  /// Index by digest for O(1) lookup during scanning.
  Map<String, ManifestEntry> get byDigest =>
      {for (final e in entries) e.digest: e};

  int get ticketCount => entries.length;

  /// Age of this manifest relative to [now] (defaults to wall-clock).
  Duration ageAt([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().difference(generatedAt.toUtc());

  /// Past the soft threshold: warn the operator, still admit.
  bool isStaleSoft([DateTime? now]) => ageAt(now) >= softStaleThreshold;

  /// Past the hard threshold: refuse offline admits, force online.
  bool isStaleHard([DateTime? now]) => ageAt(now) >= hardStaleThreshold;

  static String digestOf(String qrToken) =>
      sha256.convert(utf8.encode(qrToken)).toString();

  factory OfflineManifest.fromJson(Map<String, dynamic> j) => OfflineManifest(
        eventId: j['event_id'] as String,
        eventTitle: (j['event_title'] as String?) ?? '',
        generatedAt: DateTime.parse(j['generated_at'] as String),
        entries: ((j['tickets'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ManifestEntry.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'event_title': eventTitle,
        'generated_at': generatedAt.toIso8601String(),
        'tickets': entries.map((e) => e.toJson()).toList(),
      };
}
