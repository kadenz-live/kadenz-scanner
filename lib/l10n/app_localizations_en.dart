// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kadenz Scanner';

  @override
  String get loginTitle => 'Validator';

  @override
  String loginServer(String url) {
    return 'Server: $url';
  }

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginButton => 'Sign in';

  @override
  String loginErrorConnection(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get loginApiUnreachableBannerTitle => 'Server unreachable';

  @override
  String loginApiUnreachableBannerBody(String url) {
    return 'The scanner cannot reach $url. Check the connection or change the server in settings.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsApiBaseUrl => 'API Base URL';

  @override
  String get settingsApiBaseUrlHint => 'https://kadenz.live';

  @override
  String get settingsApiBaseUrlTips =>
      'Production: https://kadenz.live (default)\nLocal dev (iOS Sim): http://localhost:3000\nLocal dev (Android Emu): http://10.0.2.2:3000';

  @override
  String get settingsApiBaseUrlLockedByEnv =>
      'API URL is locked by the build (--dart-define=KADENZ_API).';

  @override
  String get settingsApiResolvedTitle => 'Currently used';

  @override
  String get settingsApiSourceEnv => 'Source: build env (--dart-define)';

  @override
  String get settingsApiSourceStored => 'Source: stored override';

  @override
  String get settingsApiSourceDefault => 'Source: default';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsLicenses => 'Open-source licenses';

  @override
  String get eventPickerTitle => 'Select event';

  @override
  String eventPickerLoadError(String error) {
    return 'Could not load events:\n$error';
  }

  @override
  String get eventPickerRetry => 'Try again';

  @override
  String get eventPickerEmpty => 'No upcoming events.';

  @override
  String get eventPickerAnyTitle => 'Scan any event';

  @override
  String get eventPickerAnySubtitle =>
      'Server validates event assignment from ticket.';

  @override
  String eventPickerCheckedIn(int used, int total) {
    return '$used/$total checked in';
  }

  @override
  String get scannerAnyEvent => 'Any event';

  @override
  String get scannerTooltipTorch => 'Torch';

  @override
  String get scannerTooltipCamera => 'Switch camera';

  @override
  String get scannerNetworkError => 'Network error';

  @override
  String scannerHudCheckedIn(int used, int total) {
    return '$used / $total checked in';
  }

  @override
  String scannerHudCounted(int count) {
    return '$count scanned';
  }

  @override
  String get scannerHistoryTitle => 'Recent';

  @override
  String get scannerTooltipManualEntry => 'Manual code entry';

  @override
  String get scannerManualEntryTitle => 'Manual code entry';

  @override
  String get scannerManualEntryHelp =>
      'Type the printed code (TIX-XXXXXXXX) and tap Validate.';

  @override
  String get scannerManualEntryHint => 'TIX-XXXXXXXX';

  @override
  String get scannerManualEntryCancel => 'Cancel';

  @override
  String get scannerManualEntryValidate => 'Validate';

  @override
  String get scannerStatusOk => 'OK';

  @override
  String get scannerStatusAlreadyUsed => 'ALREADY USED';

  @override
  String get scannerStatusVoid => 'VOID';

  @override
  String get scannerStatusNotFound => 'UNKNOWN TICKET';

  @override
  String get scannerStatusNetworkError => 'NO NETWORK';

  @override
  String get scannerStatusUnknown => 'ERROR';

  @override
  String get offlineMenuPrepare => 'Prepare offline mode';

  @override
  String get offlineMenuEnter => 'Start offline mode';

  @override
  String get offlineMenuExit => 'Exit offline mode';

  @override
  String offlineMenuReconcile(int count) {
    return 'Reconcile ($count)';
  }

  @override
  String offlineBannerStatus(int count) {
    return 'OFFLINE – $count scans queued';
  }

  @override
  String offlineBannerManifest(String datetime) {
    return 'Manifest: $datetime';
  }

  @override
  String get offlineBannerReconcile => 'Reconcile';

  @override
  String offlineSnackManifestLoaded(int count) {
    return 'Offline manifest loaded: $count tickets';
  }

  @override
  String offlineSnackSyncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String offlineSnackReconcileFailed(String error) {
    return 'Reconcile failed: $error';
  }

  @override
  String get reconcileTitle => 'Reconcile complete';

  @override
  String reconcileSummary(int accepted, int conflicts) {
    return '$accepted accepted · $conflicts conflict(s)';
  }

  @override
  String get reconcileNoConflicts =>
      'No conflicts — all offline scans accepted.';

  @override
  String reconcileConflictTicket(String code) {
    return 'Ticket $code';
  }

  @override
  String reconcileConflictDevices(
      String deviceA, String timeA, String deviceB) {
    return 'Device $deviceA $timeA / Device $deviceB';
  }

  @override
  String get reconcileReasonAlreadyUsed => 'Double scan';

  @override
  String get reconcileReasonNotEligible => 'Ticket not eligible';

  @override
  String get reconcileReasonUnknown => 'Unknown ticket';
}
