/// A conflict surfaced by the server during reconcile — typically a
/// double-scan across devices or against an online scan in the offline window.
class ReconcileConflict {
  const ReconcileConflict({
    required this.ticketId,
    required this.reason,
    this.deviceId,
    this.ticketCode,
    this.alreadyCheckedInAt,
    this.alreadyCheckedInBy,
  });

  final String ticketId;
  final String reason; // already_used | unknown | not_eligible
  final String? deviceId;
  final String? ticketCode;
  final DateTime? alreadyCheckedInAt;
  final String? alreadyCheckedInBy;

  factory ReconcileConflict.fromJson(Map<String, dynamic> j) => ReconcileConflict(
        ticketId: j['ticket_id'] as String,
        reason: (j['reason'] as String?) ?? 'unknown',
        deviceId: j['device_id'] as String?,
        ticketCode: j['ticket_code'] as String?,
        alreadyCheckedInAt: j['already_checked_in_at'] != null
            ? DateTime.tryParse(j['already_checked_in_at'] as String)
            : null,
        alreadyCheckedInBy: j['already_checked_in_by'] as String?,
      );
}

/// Outcome of a reconcile run.
class ReconcileResult {
  const ReconcileResult({
    required this.acceptedCount,
    required this.conflicts,
  });

  final int acceptedCount;
  final List<ReconcileConflict> conflicts;

  int get conflictCount => conflicts.length;
  bool get hasConflicts => conflicts.isNotEmpty;

  factory ReconcileResult.fromJson(Map<String, dynamic> j) => ReconcileResult(
        acceptedCount: (j['accepted_count'] as int?) ?? 0,
        conflicts: ((j['conflicts'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ReconcileConflict.fromJson)
            .toList(),
      );
}
