/// A scan captured while offline, awaiting reconcile with the server.
class QueuedScan {
  const QueuedScan({
    required this.ticketId,
    required this.scannedAt,
    required this.deviceId,
  });

  final String ticketId;
  final DateTime scannedAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'ticket_id': ticketId,
        'scanned_at': scannedAt.toUtc().toIso8601String(),
        'device_id': deviceId,
      };

  factory QueuedScan.fromJson(Map<String, dynamic> j) => QueuedScan(
        ticketId: j['ticket_id'] as String,
        scannedAt: DateTime.parse(j['scanned_at'] as String),
        deviceId: j['device_id'] as String,
      );
}
