class ScannerEvent {
  final String id;
  final String title;
  final DateTime startsAt;
  final String? venue;
  final int ticketsTotal;
  final int ticketsUsed;

  ScannerEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.ticketsTotal,
    required this.ticketsUsed,
    this.venue,
  });

  factory ScannerEvent.fromJson(Map<String, dynamic> j) => ScannerEvent(
        id: j['id'] as String,
        title: j['title'] as String,
        startsAt: DateTime.parse(j['starts_at'] as String),
        venue: j['venue'] as String?,
        ticketsTotal: j['tickets_total'] as int? ?? 0,
        ticketsUsed: j['tickets_used'] as int? ?? 0,
      );
}
