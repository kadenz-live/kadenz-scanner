import '../models/offline_manifest.dart';
import '../models/validation_result.dart';

/// Outcome of an offline scan: the result to show the operator plus, on
/// acceptance, the ticket id to enqueue for later reconcile.
class OfflineScanOutcome {
  const OfflineScanOutcome({
    required this.result,
    this.acceptedTicketId,
    this.staleWarning = false,
    this.forceOnline = false,
  });

  final ValidationResult result;

  /// Non-null only when the scan was accepted and should be queued.
  final String? acceptedTicketId;

  /// True when the manifest is past the soft threshold: the scan still counts
  /// but the operator should be prompted to re-sync soon.
  final bool staleWarning;

  /// True when the scan was refused because the manifest is past the hard
  /// staleness threshold — the operator must go back online to validate.
  final bool forceOnline;

  bool get accepted => acceptedTicketId != null;
}

/// Pure-Dart offline validation against a pre-synced manifest.
///
/// No network, no signing secret: the scanned QR token is hashed (SHA-256)
/// and matched against the manifest digest. Tickets already scanned in this
/// offline session are rejected locally to prevent same-device double entry.
///
/// Staleness gate: a manifest cannot observe revoke/refund events that happen
/// after it was generated. Past [OfflineManifest.hardStaleThreshold] this
/// validator refuses to admit any ticket and signals [OfflineScanOutcome.forceOnline]
/// so the operator revalidates against the live server. Past the softer
/// [OfflineManifest.softStaleThreshold] scans still go through but each carries
/// a [OfflineScanOutcome.staleWarning].
class OfflineValidator {
  OfflineValidator(
    this.manifest, {
    Set<String>? alreadyScanned,
    DateTime Function()? clock,
  })  : _alreadyScanned = alreadyScanned ?? <String>{},
        _byDigest = manifest.byDigest,
        _clock = clock ?? DateTime.now;

  final OfflineManifest manifest;
  final Map<String, ManifestEntry> _byDigest;
  final Set<String> _alreadyScanned;
  final DateTime Function() _clock;

  Set<String> get alreadyScanned => Set.unmodifiable(_alreadyScanned);

  OfflineScanOutcome validate(String qrToken) {
    final now = _clock();

    // Hard staleness: the manifest may pre-date a revoke/refund. Refuse to
    // admit and push the operator back online rather than risk a stale admit.
    if (manifest.isStaleHard(now)) {
      return OfflineScanOutcome(
        result: ValidationResult(
          ok: false,
          status: 'manifest_stale',
          message: 'Manifest veraltet – online prüfen (nicht offline einlassen)',
        ),
        forceOnline: true,
      );
    }

    final digest = OfflineManifest.digestOf(qrToken);
    final entry = _byDigest[digest];

    if (entry == null) {
      return _reject('not_found', 'Ticket nicht im Manifest (offline)');
    }
    if (entry.status == 'void') {
      return _reject('void', 'Ticket ungültig (storniert/erstattet)');
    }
    if (entry.status == 'used') {
      // Used at sync time — already admitted online before going offline.
      return _reject('already_used', 'Bereits eingecheckt (vor Offline-Sync)');
    }
    if (_alreadyScanned.contains(entry.id)) {
      return _reject('already_used', 'Bereits offline gescannt');
    }

    final softStale = manifest.isStaleSoft(now);
    _alreadyScanned.add(entry.id);
    return OfflineScanOutcome(
      result: ValidationResult(
        ok: true,
        status: 'ok',
        message: softStale ? 'OK (offline – Manifest veraltet, bald neu laden)' : 'OK (offline)',
        ticket: {'id': entry.id},
      ),
      acceptedTicketId: entry.id,
      staleWarning: softStale,
    );
  }

  OfflineScanOutcome _reject(String status, String message) => OfflineScanOutcome(
        result: ValidationResult(ok: false, status: status, message: message),
      );
}
