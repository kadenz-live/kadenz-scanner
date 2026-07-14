import 'package:flutter/foundation.dart';

import '../models/validation_result.dart';

/// One row in the scanner's running history.
@immutable
class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.result,
    required this.at,
  });

  final ValidationResult result;
  final DateTime at;
}

/// Pure ring-buffer-style state holder for the scanner's last-N results.
///
/// Extracted from `ScannerScreen` so the dedupe + capacity logic is testable
/// without a widget tree. Defaults to capacity 3 because the result panel
/// itself shows the live (most-recent) result already, so 3 more rows below
/// it gives door staff a four-deep recall without scrolling.
class ScanHistory {
  ScanHistory({this.capacity = 3});

  final int capacity;
  final List<ScanHistoryEntry> _entries = <ScanHistoryEntry>[];

  /// Most-recent first.
  List<ScanHistoryEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Push a new result onto the history. Consecutive duplicates (same status
  /// code AND same ticket id within a short window) collapse into the most
  /// recent one so a noisy scanner does not flood the row. The capacity gate
  /// then trims to [capacity].
  void push(ValidationResult result, DateTime at) {
    final ticketId = (result.ticket?['id'] as String?) ?? '';
    if (_entries.isNotEmpty) {
      final head = _entries.first;
      final headTicketId = (head.result.ticket?['id'] as String?) ?? '';
      final withinDedup = at.difference(head.at).abs() < const Duration(seconds: 2);
      if (withinDedup &&
          head.result.status == result.status &&
          headTicketId == ticketId) {
        return;
      }
    }
    _entries.insert(0, ScanHistoryEntry(result: result, at: at));
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
  }

  void clear() => _entries.clear();
}
