import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import '../models/reconcile_result.dart';
import '../models/scanner_event.dart';
import '../models/validation_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../audio/scan_audio.dart';
import '../services/offline_controller.dart';
import 'conflict_list_screen.dart';
import 'manual_entry_dialog.dart';
import 'scan_history.dart';
import 'scanner_status_labels.dart';

/// Lazy singleton holder for the production [ScanAudio] so the default
/// constructor argument can stay `const` while the actual instance is
/// constructed only on first read.
ScanAudio? _defaultAudio;
ScanAudio _resolveDefaultAudio() => _defaultAudio ??= ScanAudio();

class ScannerScreen extends StatefulWidget {
  ScannerScreen({
    super.key,
    required this.api,
    required this.event,
    this.authService,
    ScanAudio? audio,
  }) : audio = audio ?? _resolveDefaultAudio();
  final ApiService api;
  final ScannerEvent? event;
  final AuthService? authService;
  // Audio is injected so widget tests can swap a recording fake in place
  // of the real AudioPlayer-backed implementation. Production callers get
  // the real [ScanAudio] for free via the lazy default.
  final ScanAudio audio;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _processing = false;
  ValidationResult? _last;
  DateTime? _lastShownAt;
  String? _lastPayload;

  // Door-staff HUD state.
  // `_acceptedDelta` is incremented locally on every accepted scan so the
  // HUD reflects the current shift without round-tripping to the API for
  // a fresh `ScannerEvent` on every tap.
  final ScanHistory _history = ScanHistory();
  int _acceptedDelta = 0;

  OfflineController? _offline;

  @override
  void initState() {
    super.initState();
    _maybeInitOffline();
  }

  Future<void> _maybeInitOffline() async {
    final auth = widget.authService;
    final event = widget.event;
    // Offline mode is only meaningful for a specific event (the manifest is
    // per-event). "Any event" scanning stays online-only.
    if (auth == null || event == null) return;
    final controller = OfflineController(
      api: widget.api,
      eventId: event.id,
      deviceId: await auth.deviceId(),
    );
    controller.addListener(_onOfflineChanged);
    await controller.restore();
    if (!mounted) return;
    setState(() => _offline = controller);
  }

  void _onOfflineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _offline?.removeListener(_onOfflineChanged);
    _offline?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;

    final barcode = capture.barcodes.firstWhere(
      (b) => b.rawValue != null && b.rawValue!.isNotEmpty,
      orElse: () => const Barcode(rawValue: null, format: BarcodeFormat.unknown),
    );
    final raw = barcode.rawValue;
    if (raw == null) return;

    // Debounce identical scans within 1.5s
    if (raw == _lastPayload && _lastShownAt != null && DateTime.now().difference(_lastShownAt!) < const Duration(milliseconds: 1500)) {
      return;
    }

    setState(() { _processing = true; _lastPayload = raw; });
    try {
      final offline = _offline;
      final result = (offline != null && offline.isOffline)
          ? await offline.validateOffline(raw)
          : await widget.api.validate(payload: raw, eventId: widget.event?.id);
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _last = result;
        _lastShownAt = now;
        _history.push(result, now);
        if (result.ok) _acceptedDelta++;
      });
      // Differentiated haptic + audio feedback: light tap + high beep on
      // success, heavy thump + low buzz on any rejection — door staff feel
      // and hear the result through the phone shell even without looking at
      // the screen. Audio failure is intentionally swallowed by ScanAudio.
      unawaited(result.ok
          ? HapticFeedback.lightImpact()
          : HapticFeedback.heavyImpact());
      unawaited(result.ok ? widget.audio.playSuccess() : widget.audio.playFail());
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      final now = DateTime.now();
      final err = ValidationResult(
          ok: false, status: 'network_error', message: l.scannerNetworkError);
      setState(() {
        _last = err;
        _lastShownAt = now;
        _history.push(err, now);
      });
      unawaited(HapticFeedback.heavyImpact());
      unawaited(widget.audio.playFail());
    } finally {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _processing = false);
      });
    }
  }

  Future<void> _prepareOffline() async {
    final l = AppLocalizations.of(context)!;
    final offline = _offline;
    if (offline == null) return;
    try {
      await offline.prepareOffline();
      _snack(l.offlineSnackManifestLoaded(offline.manifestTicketCount));
    } catch (e) {
      _snack(l.offlineSnackSyncFailed(e.toString()));
    }
  }

  Future<void> _reconcile() async {
    final l = AppLocalizations.of(context)!;
    final offline = _offline;
    if (offline == null) return;
    try {
      final ReconcileResult result = await offline.reconcile();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ConflictListScreen(result: result)),
      );
    } catch (e) {
      _snack(l.offlineSnackReconcileFailed(e.toString()));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Open the manual-entry modal. Falls through to the same result/error
  /// rendering path as a camera scan so the operator's experience is
  /// consistent. Disabled when there is no concrete event selected — the
  /// backend `validate_code` endpoint requires an event_id.
  Future<void> _openManualEntry() async {
    final event = widget.event;
    if (event == null) return;
    final code = await ManualEntryDialog.show(context);
    if (code == null || !mounted) return;

    setState(() => _processing = true);
    try {
      final result = await widget.api.validateByCode(eventId: event.id, code: code);
      if (!mounted) return;
      setState(() {
        _last = result;
        _lastShownAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      setState(() {
        _last = ValidationResult(
            ok: false, status: 'network_error', message: l.scannerNetworkError);
        _lastShownAt = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final offline = _offline;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event?.title ?? l.scannerAnyEvent),
        actions: [
          if (offline != null) _offlineMenu(context, offline),
          if (widget.event != null)
            IconButton(
              icon: const Icon(Icons.keyboard_outlined),
              tooltip: l.scannerTooltipManualEntry,
              onPressed: _openManualEntry,
            ),
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: l.scannerTooltipTorch,
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            tooltip: l.scannerTooltipCamera,
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  _hudBar(context),
                  if (offline != null && offline.isOffline)
                    _offlineBanner(context, offline),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_history.isEmpty) _historyStrip(context),
                  if (_last != null) _resultPanel(_last!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top HUD with live "X / Y checked in" (or just "N scanned" when an
  /// event picker chose "Any event" and no per-event total is known).
  Widget _hudBar(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final event = widget.event;
    final String text;
    if (event != null && event.ticketsTotal > 0) {
      text = l.scannerHudCheckedIn(
        event.ticketsUsed + _acceptedDelta,
        event.ticketsTotal,
      );
    } else {
      text = l.scannerHudCounted(_acceptedDelta);
    }
    return Container(
      key: const ValueKey('scanner_hud'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.confirmation_number_outlined,
              size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
        ],
      ),
    );
  }

  /// Compact strip showing up to N recent scans below the live result.
  Widget _historyStrip(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      key: const ValueKey('scanner_history'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(l.scannerHistoryTitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                )),
          ),
          for (final entry in _history.entries) _historyRow(context, entry),
        ],
      ),
    );
  }

  Widget _historyRow(BuildContext context, ScanHistoryEntry e) {
    final r = e.result;
    final icon = r.ok
        ? Icons.check_circle
        : (r.status == 'already_used' ? Icons.error : Icons.cancel);
    final color = r.ok
        ? Colors.greenAccent
        : (r.status == 'already_used' ? Colors.amber : Colors.redAccent);
    final time = TimeOfDay.fromDateTime(e.at);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.holderName.isNotEmpty
                  ? r.holderName
                  : (r.code.isNotEmpty ? r.code : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Text(timeStr,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }

  Widget _offlineMenu(BuildContext context, OfflineController offline) {
    final l = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: Icon(offline.isOffline ? Icons.cloud_off : Icons.cloud_outlined),
      onSelected: (value) async {
        switch (value) {
          case 'prepare':
            await _prepareOffline();
            break;
          case 'enter':
            offline.enterOfflineMode();
            break;
          case 'reconcile':
            await _reconcile();
            break;
          case 'exit':
            offline.exitOfflineMode();
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'prepare',
          enabled: !offline.isBusy,
          child: Text(l.offlineMenuPrepare),
        ),
        if (offline.isReady && !offline.isOffline)
          PopupMenuItem(value: 'enter', child: Text(l.offlineMenuEnter)),
        if (offline.isOffline)
          PopupMenuItem(value: 'exit', child: Text(l.offlineMenuExit)),
        if (offline.queuedCount > 0)
          PopupMenuItem(
            value: 'reconcile',
            enabled: !offline.isBusy,
            child: Text(l.offlineMenuReconcile(offline.queuedCount)),
          ),
      ],
    );
  }

  Widget _offlineBanner(BuildContext context, OfflineController offline) {
    final l = AppLocalizations.of(context)!;
    final at = offline.manifestGeneratedAt;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fmt = DateFormat('dd.MM. HH:mm', locale);
    return Container(
      width: double.infinity,
      color: Colors.deepOrange.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${l.offlineBannerStatus(offline.queuedCount)}'
              '${at != null ? "\n${l.offlineBannerManifest(fmt.format(at.toLocal()))}" : ""}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          if (offline.queuedCount > 0)
            TextButton(
              onPressed: offline.isBusy ? null : _reconcile,
              child: Text(l.offlineBannerReconcile, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _resultPanel(ValidationResult r) {
    final color = r.ok ? Colors.green : (r.status == 'already_used' ? Colors.amber : Colors.red);
    final icon = r.ok ? Icons.check_circle : (r.status == 'already_used' ? Icons.error : Icons.cancel);
    final label = scannerStatusLabel(r, AppLocalizations.of(context)!);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 0)],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 56),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              if (r.eventTitle.isNotEmpty)
                Text(r.eventTitle, style: const TextStyle(color: Colors.white)),
              if (r.holderName.isNotEmpty || r.ticketTypeName.isNotEmpty)
                Text('${r.ticketTypeName}${r.holderName.isNotEmpty ? " · ${r.holderName}" : ""}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              if (r.code.isNotEmpty)
                Text(r.code, style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
              if (r.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(r.message, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                ),
            ],
          )),
        ],
      ),
    );
  }
}
