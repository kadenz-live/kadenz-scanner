import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/scanner_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class EventPickerScreen extends StatefulWidget {
  const EventPickerScreen({super.key, required this.authService, this.api});
  final AuthService authService;

  /// Optional injection for tests — production code always falls back to
  /// constructing a fresh [ApiService] from [authService] so the existing
  /// callers do not need to change.
  final ApiService? api;

  @override
  State<EventPickerScreen> createState() => _EventPickerScreenState();
}

class _EventPickerScreenState extends State<EventPickerScreen> {
  late final ApiService _api = widget.api ?? ApiService(widget.authService);
  Future<List<ScannerEvent>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    // Wrap in a block so the closure returns void — Flutter rejects a
    // setState callback whose body evaluates to a Future (the assignment's
    // right-hand-side here is `_api.events()`, which is a Future).
    setState(() {
      _future = _api.events();
    });
  }

  Future<void> _logout() async {
    await widget.authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LoginScreen(authService: widget.authService),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.eventPickerTitle),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(authService: widget.authService)));
            _refresh();
          }),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: FutureBuilder<List<ScannerEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber.shade400),
                    const SizedBox(height: 12),
                    Text(l.eventPickerLoadError(snap.error.toString()), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: Text(l.eventPickerRetry)),
                  ],
                ),
              ),
            );
          }
          final events = snap.data ?? [];
          if (events.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.eventPickerEmpty, textAlign: TextAlign.center),
            ));
          }

          // "All events" sentinel for general scanning
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, i) {
              if (i == 0) return _eventCard(context, null);
              return _eventCard(context, events[i - 1]);
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: events.length + 1,
          );
        },
      ),
    );
  }

  Widget _eventCard(BuildContext context, ScannerEvent? event) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fmt = DateFormat('EEE dd.MM.yyyy HH:mm', locale);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ScannerScreen(api: _api, event: event, authService: widget.authService),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: event == null
                    ? [Colors.grey.shade700, Colors.grey.shade900]
                    : [const Color(0xFF7c3aed), const Color(0xFF06b6d4)]),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event?.title ?? l.eventPickerAnyTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  if (event != null) ...[
                    Text('${fmt.format(event.startsAt)}${event.venue != null ? " · ${event.venue}" : ""}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(l.eventPickerCheckedIn(event.ticketsUsed, event.ticketsTotal),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                  ] else ...[
                    Text(l.eventPickerAnySubtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ],
              )),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
