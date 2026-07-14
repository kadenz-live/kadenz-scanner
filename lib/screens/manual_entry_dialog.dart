import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Normalises a manual ticket-code input: uppercases, strips internal
/// whitespace, leaves the hyphen intact. Door staff sometimes type
/// "tix abc 1234" or "TIX—…" (em-dash); the backend expects the canonical
/// `TIX-XXXXXXXX` form (and itself upcases server-side defensively).
String normaliseManualCode(String raw) {
  return raw
      .replaceAll(RegExp(r'[\s–—]'), '')
      .replaceAll(RegExp(r'—|–'), '-')
      .toUpperCase();
}

/// True when [code] looks plausibly like a TIX code — `TIX-` prefix and at
/// least 4 trailing characters. Server-side is the source of truth; this is
/// only a frontend gate to suppress an obvious accidental submit.
bool isLikelyTicketCode(String code) {
  final normalised = normaliseManualCode(code);
  return RegExp(r'^TIX-[A-Z0-9]{4,}$').hasMatch(normalised);
}

/// Modal that collects a printed ticket code and returns the normalised
/// value on submit (or `null` on cancel). Pure UI — no API call here so the
/// caller can plug it into the same haptic / history pipeline as a scan.
class ManualEntryDialog extends StatefulWidget {
  const ManualEntryDialog({super.key});

  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();

  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      builder: (_) => const ManualEntryDialog(),
    );
  }
}

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  final TextEditingController _controller = TextEditingController();
  String _normalised = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final n = normaliseManualCode(_controller.text);
      if (n != _normalised) setState(() => _normalised = n);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!isLikelyTicketCode(_controller.text)) return;
    Navigator.of(context).pop(normaliseManualCode(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final valid = isLikelyTicketCode(_controller.text);
    return AlertDialog(
      title: Text(l.scannerManualEntryTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.scannerManualEntryHelp,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              )),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('manual_entry_field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.visiblePassword,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(40),
            ],
            decoration: InputDecoration(
              hintText: l.scannerManualEntryHint,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              letterSpacing: 1.2,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.scannerManualEntryCancel),
        ),
        FilledButton(
          onPressed: valid ? _submit : null,
          child: Text(l.scannerManualEntryValidate),
        ),
      ],
    );
  }
}
