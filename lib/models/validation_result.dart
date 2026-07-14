class ValidationResult {
  final bool ok;
  final String status;
  final String message;
  final Map<String, dynamic>? ticket;

  ValidationResult({
    required this.ok,
    required this.status,
    required this.message,
    this.ticket,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> j) => ValidationResult(
        ok: j['ok'] as bool? ?? false,
        status: (j['status'] as String?) ?? 'unknown',
        message: (j['message'] as String?) ?? '',
        ticket: j['ticket'] as Map<String, dynamic>?,
      );

  String get holderName => (ticket?['holder_name'] as String?) ?? '';
  String get ticketTypeName => ((ticket?['ticket_type'] as Map?)?['name'] as String?) ?? '';
  String get eventTitle => ((ticket?['event'] as Map?)?['title'] as String?) ?? '';
  String get code => (ticket?['code'] as String?) ?? '';
}
