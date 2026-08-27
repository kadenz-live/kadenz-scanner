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
    this.validUntil,
  });

  final String eventId;
  final String eventTitle;
  final DateTime generatedAt;
  final List<ManifestEntry> entries;

  /// Server-side offline-validity deadline (kadenz#1778).
  ///
  /// When present it is **authoritative in both directions** for the hard
  /// staleness gate — see [isStaleHard]:
  ///
  ///  * server says expired  → stale, even if the manifest is younger than
  ///    [hardStaleThreshold]. Refusing fails safe: worst case the operator is
  ///    forced online; admitting from an expired manifest could let a
  ///    revoked/refunded ticket through, which is unrecoverable at the door.
  ///    **An expired manifest must NEVER admit.**
  ///  * server says still valid → not stale, even past [hardStaleThreshold].
  ///    That is the point of moving the policy server-side: the server knows
  ///    event timing (e.g. multi-day events) and can extend or shorten the
  ///    window without an app release.
  ///
  /// `null` when the server predates the field — [isStaleHard] then falls
  /// back to the [hardStaleThreshold] constant (backward compatible across
  /// one release cycle).
  final DateTime? validUntil;

  /// Soft threshold: past this age the operator sees a prominent
  /// stale-manifest warning but scans still go through. Re-sync recommended.
  static const Duration softStaleThreshold = Duration(hours: 2);

  /// Hard threshold: past this age offline validation refuses to admit any
  /// ticket. A manifest this old may not reflect revoke/refund events since
  /// the last sync, so we force the operator back online rather than risk
  /// admitting a ticket that was revoked after the manifest was generated.
  ///
  /// Fallback only (kadenz#1778): applied to [generatedAt] when the server
  /// did not ship a [validUntil]. When [validUntil] is present it is
  /// authoritative and this constant is ignored — see [isStaleHard].
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

  /// Hard staleness gate: refuse offline admits, force online.
  ///
  /// Authority order (kadenz#1778, see [validUntil]): a server-provided
  /// `valid_until` wins over the [hardStaleThreshold] constant in both
  /// directions. The deadline itself counts as expired (`now >= validUntil`)
  /// — at the expiry instant the manifest must already refuse, matching the
  /// server's `valid_until <= now` semantics. An expired manifest must
  /// NEVER admit.
  bool isStaleHard([DateTime? now]) {
    final deadline = validUntil;
    final reference = (now ?? DateTime.now()).toUtc();
    if (deadline != null) {
      return !reference.isBefore(deadline.toUtc());
    }
    return ageAt(now) >= hardStaleThreshold;
  }

  static String digestOf(String qrToken) =>
      sha256.convert(utf8.encode(qrToken)).toString();

  factory OfflineManifest.fromJson(Map<String, dynamic> j) {
    // Absent on pre-#1778 servers → null → hardStaleThreshold fallback.
    final rawValidUntil = j['valid_until'] as String?;
    return OfflineManifest(
      eventId: j['event_id'] as String,
      eventTitle: (j['event_title'] as String?) ?? '',
      generatedAt: DateTime.parse(j['generated_at'] as String),
      entries: ((j['tickets'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ManifestEntry.fromJson)
          .toList(),
      validUntil:
          rawValidUntil == null ? null : DateTime.parse(rawValidUntil),
    );
  }

  Map<String, dynamic> toJson() {
    // valid_until MUST round-trip through the offline store: dropping it on
    // persist would silently demote a server-expired manifest to the 12h
    // fallback after an app relaunch — the unsafe direction.
    final deadline = validUntil;
    return {
      'event_id': eventId,
      'event_title': eventTitle,
      'generated_at': generatedAt.toIso8601String(),
      if (deadline != null) 'valid_until': deadline.toIso8601String(),
      'tickets': entries.map((e) => e.toJson()).toList(),
    };
  }
}
