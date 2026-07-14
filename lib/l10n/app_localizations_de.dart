// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Kadenz Scanner';

  @override
  String get loginTitle => 'Validator';

  @override
  String loginServer(String url) {
    return 'Server: $url';
  }

  @override
  String get loginEmail => 'E-Mail';

  @override
  String get loginPassword => 'Passwort';

  @override
  String get loginButton => 'Anmelden';

  @override
  String loginErrorConnection(String error) {
    return 'Verbindung fehlgeschlagen: $error';
  }

  @override
  String get loginApiUnreachableBannerTitle => 'Server nicht erreichbar';

  @override
  String loginApiUnreachableBannerBody(String url) {
    return 'Der Scanner erreicht $url nicht. Verbindung prüfen oder Server in den Einstellungen ändern.';
  }

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsApiBaseUrl => 'API-Basis-URL';

  @override
  String get settingsApiBaseUrlHint => 'https://kadenz.live';

  @override
  String get settingsApiBaseUrlTips =>
      'Produktion: https://kadenz.live (Standard)\nLokale Entwicklung (iOS-Sim): http://localhost:3000\nLokale Entwicklung (Android-Emu): http://10.0.2.2:3000';

  @override
  String get settingsApiBaseUrlLockedByEnv =>
      'Die API-URL ist durch den Build festgelegt (--dart-define=KADENZ_API).';

  @override
  String get settingsApiResolvedTitle => 'Aktuell verwendet';

  @override
  String get settingsApiSourceEnv => 'Quelle: Build-Env (--dart-define)';

  @override
  String get settingsApiSourceStored => 'Quelle: gespeicherter Override';

  @override
  String get settingsApiSourceDefault => 'Quelle: Standard';

  @override
  String get settingsSave => 'Speichern';

  @override
  String get settingsLicenses => 'Open-Source-Lizenzen';

  @override
  String get eventPickerTitle => 'Event auswählen';

  @override
  String eventPickerLoadError(String error) {
    return 'Konnte Events nicht laden:\n$error';
  }

  @override
  String get eventPickerRetry => 'Erneut versuchen';

  @override
  String get eventPickerEmpty => 'Keine kommenden Events.';

  @override
  String get eventPickerAnyTitle => 'Beliebiges Event scannen';

  @override
  String get eventPickerAnySubtitle =>
      'Server validiert die Event-Zuordnung anhand des Tickets.';

  @override
  String eventPickerCheckedIn(int used, int total) {
    return '$used/$total eingecheckt';
  }

  @override
  String get scannerAnyEvent => 'Beliebiges Event';

  @override
  String get scannerTooltipTorch => 'Taschenlampe';

  @override
  String get scannerTooltipCamera => 'Kamera wechseln';

  @override
  String get scannerNetworkError => 'Netzwerkfehler';

  @override
  String scannerHudCheckedIn(int used, int total) {
    return '$used / $total eingecheckt';
  }

  @override
  String scannerHudCounted(int count) {
    return '$count gescannt';
  }

  @override
  String get scannerHistoryTitle => 'Zuletzt';

  @override
  String get scannerTooltipManualEntry => 'Code manuell eingeben';

  @override
  String get scannerManualEntryTitle => 'Code manuell eingeben';

  @override
  String get scannerManualEntryHelp =>
      'Aufgedruckten Code (TIX-XXXXXXXX) eingeben und auf Prüfen tippen.';

  @override
  String get scannerManualEntryHint => 'TIX-XXXXXXXX';

  @override
  String get scannerManualEntryCancel => 'Abbrechen';

  @override
  String get scannerManualEntryValidate => 'Prüfen';

  @override
  String get scannerStatusOk => 'OK';

  @override
  String get scannerStatusAlreadyUsed => 'BEREITS GENUTZT';

  @override
  String get scannerStatusVoid => 'UNGÜLTIG';

  @override
  String get scannerStatusNotFound => 'UNBEKANNT';

  @override
  String get scannerStatusNetworkError => 'KEIN NETZ';

  @override
  String get scannerStatusUnknown => 'FEHLER';

  @override
  String get offlineMenuPrepare => 'Offline-Modus vorbereiten';

  @override
  String get offlineMenuEnter => 'Offline-Modus starten';

  @override
  String get offlineMenuExit => 'Offline-Modus verlassen';

  @override
  String offlineMenuReconcile(int count) {
    return 'Abgleichen ($count)';
  }

  @override
  String offlineBannerStatus(int count) {
    return 'OFFLINE – $count Scans in Warteschlange';
  }

  @override
  String offlineBannerManifest(String datetime) {
    return 'Manifest: $datetime';
  }

  @override
  String get offlineBannerReconcile => 'Abgleichen';

  @override
  String offlineSnackManifestLoaded(int count) {
    return 'Offline-Manifest geladen: $count Tickets';
  }

  @override
  String offlineSnackSyncFailed(String error) {
    return 'Sync fehlgeschlagen: $error';
  }

  @override
  String offlineSnackReconcileFailed(String error) {
    return 'Abgleich fehlgeschlagen: $error';
  }

  @override
  String get reconcileTitle => 'Abgleich abgeschlossen';

  @override
  String reconcileSummary(int accepted, int conflicts) {
    return '$accepted übernommen · $conflicts Konflikt(e)';
  }

  @override
  String get reconcileNoConflicts =>
      'Keine Konflikte — alle Offline-Scans übernommen.';

  @override
  String reconcileConflictTicket(String code) {
    return 'Ticket $code';
  }

  @override
  String reconcileConflictDevices(
      String deviceA, String timeA, String deviceB) {
    return 'Gerät $deviceA $timeA / Gerät $deviceB';
  }

  @override
  String get reconcileReasonAlreadyUsed => 'Doppel-Scan';

  @override
  String get reconcileReasonNotEligible => 'Ticket nicht gültig';

  @override
  String get reconcileReasonUnknown => 'Unbekanntes Ticket';
}
