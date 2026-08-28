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

/// How much authority a manifest carries (kadenz#1823, ADR-0055 §C).
///
/// Lives on the model rather than next to the verifier so that a manifest can
/// never be held without its provenance travelling with it.
enum ManifestTrust {
  /// The whole document was verified against a pinned Ed25519 public key: the
  /// admissible set, every entry status, and `valid_until` are server
  /// assertions rather than local state.
  signed,

  /// Not verified — either the API does not sign yet, or it signs with a key
  /// this build does not hold. Accepted only until this device has verified a
  /// signed manifest at least once; see `ManifestVerifier`.
  unsigned,
}

/// The offline-validation manifest for one event.
///
/// The HMAC signing secret never reaches the device. Validation works by
/// hashing the scanned QR token (SHA-256) and matching it against the
/// precomputed [ManifestEntry.digest] — a forged token cannot produce a
/// matching digest without the server-side secret.
///
/// ## The QR token is opaque to this app — keep it that way (kadenz#1827)
///
/// The server signs QR tokens from a **keyring**: each token names the key
/// that signed it (an optional `k` claim inside the signed payload, absent for
/// key 1), so the signing secret can be rotated without invalidating tickets
/// already sitting in wallets. See kadenz ADR-0055.
///
/// The client survives that entirely because it never looks *inside* a token:
/// online it forwards the scanned string verbatim to `/validate`, offline it
/// hashes the whole string with [digestOf]. Adding a claim changes the token's
/// bytes, and therefore its digest — which the server recomputes from the same
/// bytes, so the two still agree.
///
/// That is a contract, not a coincidence. Do **not** teach this app to
/// base64-decode a token, parse its JSON, or read `eid`/`tid`/`v`/`k` out of
/// it — not for a display label, not to pre-filter a scan, not as an
/// optimisation. Doing so re-couples the client to the payload format and
/// turns a server-side key rotation into a door outage that only shows up at
/// the gate. Ticket identity comes from [ManifestEntry.id] offline and from
/// the server response online.
class OfflineManifest {
  const OfflineManifest({
    required this.eventId,
    required this.eventTitle,
    required this.generatedAt,
    required this.entries,
    this.validUntil,
    this.eventState,
    this.manifestVersion,
    this.trust = ManifestTrust.unsigned,
  });

  final String eventId;
  final String eventTitle;
  final DateTime generatedAt;
  final List<ManifestEntry> entries;

  /// Server-side event state: `open | cancelled | cutoff_reached`. Carried so
  /// it is available to the offline decision; not yet gated on (kadenz#1823
  /// follow-up). Cancelled and cutoff manifests already ship an empty
  /// allow-list, so they admit nobody regardless.
  final String? eventState;

  /// Monotonic counter bumped by every cascade write-path on the server. Used
  /// as a freshness oracle on the next online poll; carried, not yet gated on.
  final int? manifestVersion;

  /// Whether this document was verified (kadenz#1823, ADR-0055).
  ///
  /// Defaults to [ManifestTrust.unsigned] so anything constructed by hand — a
  /// test, a legacy record replayed out of storage — is never silently treated
  /// as verified. Trust has to be earned by going through `ManifestVerifier`.
  final ManifestTrust trust;

  bool get isSigned => trust == ManifestTrust.signed;

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

  /// SHA-256 of the **entire** scanned token, byte for byte.
  ///
  /// The whole string is the input — prefix, separator, signature and any
  /// future claim. Hashing a substring (say, only the payload half) would
  /// break the moment the server changed anything the digest is supposed to
  /// cover, and would drop the signature out of the hashed material.
  static String digestOf(String qrToken) =>
      sha256.convert(utf8.encode(qrToken)).toString();

  /// [trust] is required from the caller rather than inferred from the JSON,
  /// because the presence of a `signature` key proves nothing on its own — only
  /// `ManifestVerifier` knows whether it checked out.
  factory OfflineManifest.fromJson(
    Map<String, dynamic> j, {
    ManifestTrust trust = ManifestTrust.unsigned,
  }) {
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
      eventState: j['event_state'] as String?,
      manifestVersion: j['manifest_version'] as int?,
      trust: trust,
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
      if (eventState != null) 'event_state': eventState,
      if (manifestVersion != null) 'manifest_version': manifestVersion,
      'tickets': entries.map((e) => e.toJson()).toList(),
    };
  }
}
