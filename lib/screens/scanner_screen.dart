import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../camera/mobile_scan_camera.dart';
import '../camera/scan_camera.dart';
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

/// An action the camera-fault panel can offer, in render order.
///
/// Kept as a closed set so the panel can be reasoned about as a table of
/// (fault x entry mode) -> actions, and so a widget test can pin that every
/// cell of that table has at least one entry.
enum _FaultAction {
  /// Restart the camera. Only meaningful where a restart can change anything.
  retry,

  /// Open the manual-entry modal. Requires a concrete event.
  manualEntry,

  /// Back to the event picker — the step that makes manual entry reachable.
  selectEvent,
}

class ScannerScreen extends StatefulWidget {
  ScannerScreen({
    super.key,
    required this.api,
    required this.event,
    this.authService,
    ScanAudio? audio,
    ScanCamera Function()? cameraFactory,
  })  : audio = audio ?? _resolveDefaultAudio(),
        cameraFactory = cameraFactory ?? MobileScanCamera.new;
  final ApiService api;
  final ScannerEvent? event;
  final AuthService? authService;
  // Audio is injected so widget tests can swap a recording fake in place
  // of the real AudioPlayer-backed implementation. Production callers get
  // the real [ScanAudio] for free via the lazy default.
  final ScanAudio audio;
  // Camera is injected as a factory (same shape as ScanAudio's playerFactory)
  // because the screen owns the instance's lifetime: it builds one in
  // initState and disposes it. Production gets [MobileScanCamera]; widget
  // tests pass a fake that pushes payloads and faults on demand.
  final ScanCamera Function() cameraFactory;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  late final ScanCamera _camera;
  StreamSubscription<String>? _detections;
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
    _camera = widget.cameraFactory();
    _detections =
        _camera.payloads.listen((payload) => unawaited(_onPayload(payload)));
    WidgetsBinding.instance.addObserver(this);
    // The camera may only be started once its preview is mounted — starting
    // from initState would race the first frame and the plugin would report
    // `controllerNotAttached`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_camera.start());
    });
    unawaited(_maybeInitOffline());
  }

  /// Mirror of the plugin's own lifecycle policy for an app-owned controller:
  /// release the camera when the app goes inactive (a call, control centre,
  /// the app switcher) and take it back on resume. Without this the preview
  /// comes back frozen after a phone call — the door then stares at a still
  /// image that never scans.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_camera.status.value.fault == ScanCameraFault.permissionDenied) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        unawaited(_camera.start());
      case AppLifecycleState.inactive:
        unawaited(_camera.stop());
    }
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
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_detections?.cancel());
    _detections = null;
    unawaited(_camera.dispose());
    _offline?.removeListener(_onOfflineChanged);
    _offline?.dispose();
    super.dispose();
  }

  /// One detection from the camera: a non-empty raw QR payload.
  ///
  /// Two guards stand between a detection and a door decision, in this order:
  /// `_processing` (a validation is already in flight) and the 1.5 s
  /// same-payload debounce (the operator is still holding the same phone in
  /// front of the lens). Both are what stops a single ticket being burned
  /// twice by the continuous detection stream.
  Future<void> _onPayload(String raw) async {
    if (_processing) return;

    // Debounce identical scans within 1.5s
    final shownAt = _lastShownAt;
    if (raw == _lastPayload &&
        shownAt != null &&
        DateTime.now().difference(shownAt) < const Duration(milliseconds: 1500)) {
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
        MaterialPageRoute<void>(builder: (_) => ConflictListScreen(result: result)),
      );
    } catch (e) {
      _snack(l.offlineSnackReconcileFailed(e.toString()));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether manual code entry can be offered at all.
  ///
  /// The backend `validate_code` endpoint is event-scoped, so "Any event"
  /// scanning has no manual fallback. This single predicate gates the app-bar
  /// control, the fault panel's manual-entry button *and* the fault panel's
  /// hint text, so the three can never drift apart and promise a control that
  /// is not on screen (Lektor L-05).
  bool get _manualEntryAvailable => widget.event != null;

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
    // The whole screen is rebuilt from one camera snapshot: torch + facing
    // affordances and the fault panel all read from the same [ScanCameraStatus]
    // so they can never disagree about what the camera is doing.
    return ValueListenableBuilder<ScanCameraStatus>(
      valueListenable: _camera.status,
      builder: (context, status, _) => _buildScreen(context, status),
    );
  }

  Widget _buildScreen(BuildContext context, ScanCameraStatus status) {
    final l = AppLocalizations.of(context)!;
    final offline = _offline;
    final fault = status.fault;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event?.title ?? l.scannerAnyEvent),
        actions: [
          if (offline != null) _offlineMenu(context, offline),
          if (_manualEntryAvailable)
            IconButton(
              icon: const Icon(Icons.keyboard_outlined),
              tooltip: l.scannerTooltipManualEntry,
              onPressed: _openManualEntry,
            ),
          IconButton(
            key: const ValueKey('scanner_torch'),
            icon: Icon(status.torch == ScanTorch.on
                ? Icons.flashlight_on
                : Icons.flashlight_off_outlined),
            tooltip: l.scannerTooltipTorch,
            // A camera without a controllable torch (most front cameras) gets
            // a disabled button rather than a control that silently does
            // nothing when the operator taps it in the dark.
            onPressed: status.torch == ScanTorch.unavailable
                ? null
                : () => unawaited(_camera.toggleTorch()),
          ),
          IconButton(
            key: const ValueKey('scanner_camera_switch'),
            icon: Icon(status.facing == ScanCameraFacing.front
                ? Icons.camera_front_outlined
                : Icons.cameraswitch_outlined),
            tooltip: l.scannerTooltipCamera,
            onPressed: () => unawaited(_camera.switchCamera()),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (fault == null)
            _camera.buildPreview(context)
          else
            _cameraFaultPanel(context, fault),
          if (fault == null)
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

  /// Title, hint and offered actions for one camera fault.
  ///
  /// Pure and total: the panel renders exactly what this returns, so the hint
  /// and the buttons are decided in one place from one predicate
  /// ([_manualEntryAvailable]) and cannot contradict each other.
  ///
  /// Two rules encoded here:
  /// * Retry is only offered where a restart can plausibly help
  ///   (`permissionDenied` after the operator grants access, `unknown`).
  ///   For `unsupported` no restart makes absent hardware appear, so retry
  ///   would be the button that never works.
  /// * Manual entry is only named — in the hint and as a button — when the
  ///   event-scoped control actually exists. Otherwise the operator is sent
  ///   back to the picker, which is the step that unlocks it.
  ({String title, String hint, List<_FaultAction> actions}) _faultPlan(
    AppLocalizations l,
    ScanCameraFault fault,
  ) {
    final manual = _manualEntryAvailable;
    // The escape hatch out of a dead camera: manual entry where it works,
    // otherwise back to the picker to select an event first.
    final escape = manual ? _FaultAction.manualEntry : _FaultAction.selectEvent;
    final hint =
        manual ? l.scannerCameraFaultHint : l.scannerCameraFaultHintNoEvent;
    return switch (fault) {
      ScanCameraFault.permissionDenied => (
          title: l.scannerCameraPermissionDenied,
          hint: l.scannerCameraPermissionHint,
          actions: [
            _FaultAction.retry,
            if (manual) _FaultAction.manualEntry,
          ],
        ),
      ScanCameraFault.unsupported => (
          title: l.scannerCameraUnsupported,
          hint: hint,
          actions: [escape],
        ),
      ScanCameraFault.unknown => (
          title: l.scannerCameraError,
          hint: hint,
          actions: [_FaultAction.retry, escape],
        ),
    };
  }

  /// One fault-panel button. The first action of a plan is the primary
  /// (filled) one; the rest are text buttons, forced white so they keep
  /// contrast on the panel's black backdrop.
  Widget _faultActionButton(_FaultAction action, {required bool primary}) {
    final l = AppLocalizations.of(context)!;
    final (Key key, String label, VoidCallback onPressed) = switch (action) {
      _FaultAction.retry => (
          const ValueKey('scanner_camera_retry'),
          l.scannerCameraRetry,
          () => unawaited(_camera.start()),
        ),
      // Deliberately the same label as the app-bar control it mirrors: one
      // action, one name.
      _FaultAction.manualEntry => (
          const ValueKey('scanner_camera_manual_entry'),
          l.scannerTooltipManualEntry,
          () => unawaited(_openManualEntry()),
        ),
      // `maybePop` rather than `pop`: the scanner is always pushed from the
      // picker in production, and a route that cannot pop must not throw.
      _FaultAction.selectEvent => (
          const ValueKey('scanner_camera_select_event'),
          l.scannerCameraSelectEvent,
          () => unawaited(Navigator.of(context).maybePop<void>()),
        ),
    };
    if (primary) {
      return FilledButton(key: key, onPressed: onPressed, child: Text(label));
    }
    return TextButton(
      key: key,
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  /// Blocking panel shown in place of the preview when the camera cannot run.
  ///
  /// Door-staff terse: what is wrong, the one thing that fixes it, and only
  /// actions that can actually be taken from here — every fault and entry
  /// mode leaves at least one.
  Widget _cameraFaultPanel(BuildContext context, ScanCameraFault fault) {
    final l = AppLocalizations.of(context)!;
    final plan = _faultPlan(l, fault);
    final title = plan.title;
    final hint = plan.hint;
    return Semantics(
      key: const ValueKey('scanner_camera_fault'),
      container: true,
      liveRegion: true,
      label: '$title. $hint',
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined,
                    color: Colors.white70, size: 56),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                for (final (index, action) in plan.actions.indexed) ...[
                  if (index > 0) const SizedBox(height: 4),
                  _faultActionButton(action, primary: index == 0),
                ],
              ],
            ),
          ),
        ),
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

    // The panel is colour-coded for sighted operators; the live region makes
    // the same verdict reach VoiceOver / TalkBack without a focus change.
    return Semantics(
      key: const ValueKey('scanner_result'),
      container: true,
      liveRegion: true,
      label: '$label${r.message.isNotEmpty ? '. ${r.message}' : ''}',
      child: AnimatedContainer(
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
      ),
    );
  }
}
