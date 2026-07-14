import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/reconcile_result.dart';

/// Reviewable list of conflicts returned by reconcile — typically
/// double-scans across devices in the offline window.
class ConflictListScreen extends StatelessWidget {
  const ConflictListScreen({super.key, required this.result});
  final ReconcileResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.reconcileTitle)),
      body: Column(
        children: [
          _summary(context),
          const Divider(height: 1),
          Expanded(
            child: result.hasConflicts
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: result.conflicts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _conflictCard(context, result.conflicts[i]),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.reconcileNoConflicts, textAlign: TextAlign.center),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(result.hasConflicts ? Icons.warning_amber_rounded : Icons.check_circle,
              color: result.hasConflicts ? Colors.amber : Colors.green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.reconcileSummary(result.acceptedCount, result.conflictCount),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictCard(BuildContext context, ReconcileConflict c) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fmt = DateFormat('HH:mm', locale);
    return Material(
      color: Colors.amber.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_reasonLabel(l, c.reason), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(l.reconcileConflictTicket(c.ticketCode ?? c.ticketId),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            if (c.reason == 'already_used') ...[
              const SizedBox(height: 6),
              Text(
                l.reconcileConflictDevices(
                  c.alreadyCheckedInBy ?? '?',
                  c.alreadyCheckedInAt != null ? fmt.format(c.alreadyCheckedInAt!.toLocal()) : '',
                  c.deviceId ?? '?',
                ),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _reasonLabel(AppLocalizations l, String reason) {
    switch (reason) {
      case 'already_used':
        return l.reconcileReasonAlreadyUsed;
      case 'not_eligible':
        return l.reconcileReasonNotEligible;
      case 'unknown':
        return l.reconcileReasonUnknown;
      default:
        return reason;
    }
  }
}
