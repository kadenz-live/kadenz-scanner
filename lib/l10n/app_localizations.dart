import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Kadenz Scanner'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In de, this message translates to:
  /// **'Validator'**
  String get loginTitle;

  /// No description provided for @loginServer.
  ///
  /// In de, this message translates to:
  /// **'Server: {url}'**
  String loginServer(String url);

  /// No description provided for @loginEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get loginPassword;

  /// No description provided for @loginButton.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get loginButton;

  /// No description provided for @loginErrorConnection.
  ///
  /// In de, this message translates to:
  /// **'Verbindung fehlgeschlagen: {error}'**
  String loginErrorConnection(String error);

  /// No description provided for @loginApiUnreachableBannerTitle.
  ///
  /// In de, this message translates to:
  /// **'Server nicht erreichbar'**
  String get loginApiUnreachableBannerTitle;

  /// No description provided for @loginApiUnreachableBannerBody.
  ///
  /// In de, this message translates to:
  /// **'Der Scanner erreicht {url} nicht. Verbindung prüfen oder Server in den Einstellungen ändern.'**
  String loginApiUnreachableBannerBody(String url);

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @settingsApiBaseUrl.
  ///
  /// In de, this message translates to:
  /// **'API-Basis-URL'**
  String get settingsApiBaseUrl;

  /// No description provided for @settingsApiBaseUrlHint.
  ///
  /// In de, this message translates to:
  /// **'https://kadenz.live'**
  String get settingsApiBaseUrlHint;

  /// No description provided for @settingsApiBaseUrlTips.
  ///
  /// In de, this message translates to:
  /// **'Produktion: https://kadenz.live (Standard)\nLokale Entwicklung (iOS-Sim): http://localhost:3000\nLokale Entwicklung (Android-Emu): http://10.0.2.2:3000'**
  String get settingsApiBaseUrlTips;

  /// No description provided for @settingsApiBaseUrlLockedByEnv.
  ///
  /// In de, this message translates to:
  /// **'Die API-URL ist durch den Build festgelegt (--dart-define=KADENZ_API).'**
  String get settingsApiBaseUrlLockedByEnv;

  /// No description provided for @settingsApiResolvedTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktuell verwendet'**
  String get settingsApiResolvedTitle;

  /// No description provided for @settingsApiSourceEnv.
  ///
  /// In de, this message translates to:
  /// **'Quelle: Build-Env (--dart-define)'**
  String get settingsApiSourceEnv;

  /// No description provided for @settingsApiSourceStored.
  ///
  /// In de, this message translates to:
  /// **'Quelle: gespeicherter Override'**
  String get settingsApiSourceStored;

  /// No description provided for @settingsApiSourceDefault.
  ///
  /// In de, this message translates to:
  /// **'Quelle: Standard'**
  String get settingsApiSourceDefault;

  /// No description provided for @settingsSave.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get settingsSave;

  /// No description provided for @settingsLicenses.
  ///
  /// In de, this message translates to:
  /// **'Open-Source-Lizenzen'**
  String get settingsLicenses;

  /// No description provided for @eventPickerTitle.
  ///
  /// In de, this message translates to:
  /// **'Event auswählen'**
  String get eventPickerTitle;

  /// No description provided for @eventPickerLoadError.
  ///
  /// In de, this message translates to:
  /// **'Konnte Events nicht laden:\n{error}'**
  String eventPickerLoadError(String error);

  /// No description provided for @eventPickerRetry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get eventPickerRetry;

  /// No description provided for @eventPickerEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine kommenden Events.'**
  String get eventPickerEmpty;

  /// No description provided for @eventPickerAnyTitle.
  ///
  /// In de, this message translates to:
  /// **'Beliebiges Event scannen'**
  String get eventPickerAnyTitle;

  /// No description provided for @eventPickerAnySubtitle.
  ///
  /// In de, this message translates to:
  /// **'Server validiert die Event-Zuordnung anhand des Tickets.'**
  String get eventPickerAnySubtitle;

  /// No description provided for @eventPickerCheckedIn.
  ///
  /// In de, this message translates to:
  /// **'{used}/{total} eingecheckt'**
  String eventPickerCheckedIn(int used, int total);

  /// No description provided for @scannerAnyEvent.
  ///
  /// In de, this message translates to:
  /// **'Beliebiges Event'**
  String get scannerAnyEvent;

  /// No description provided for @scannerTooltipTorch.
  ///
  /// In de, this message translates to:
  /// **'Taschenlampe'**
  String get scannerTooltipTorch;

  /// No description provided for @scannerTooltipCamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera wechseln'**
  String get scannerTooltipCamera;

  /// No description provided for @scannerNetworkError.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkfehler'**
  String get scannerNetworkError;

  /// No description provided for @scannerHudCheckedIn.
  ///
  /// In de, this message translates to:
  /// **'{used} / {total} eingecheckt'**
  String scannerHudCheckedIn(int used, int total);

  /// No description provided for @scannerHudCounted.
  ///
  /// In de, this message translates to:
  /// **'{count} gescannt'**
  String scannerHudCounted(int count);

  /// No description provided for @scannerHistoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt'**
  String get scannerHistoryTitle;

  /// No description provided for @scannerTooltipManualEntry.
  ///
  /// In de, this message translates to:
  /// **'Code manuell eingeben'**
  String get scannerTooltipManualEntry;

  /// No description provided for @scannerManualEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Code manuell eingeben'**
  String get scannerManualEntryTitle;

  /// No description provided for @scannerManualEntryHelp.
  ///
  /// In de, this message translates to:
  /// **'Aufgedruckten Code (TIX-XXXXXXXX) eingeben und auf Prüfen tippen.'**
  String get scannerManualEntryHelp;

  /// No description provided for @scannerManualEntryHint.
  ///
  /// In de, this message translates to:
  /// **'TIX-XXXXXXXX'**
  String get scannerManualEntryHint;

  /// No description provided for @scannerManualEntryCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get scannerManualEntryCancel;

  /// No description provided for @scannerManualEntryValidate.
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get scannerManualEntryValidate;

  /// No description provided for @scannerStatusOk.
  ///
  /// In de, this message translates to:
  /// **'OK'**
  String get scannerStatusOk;

  /// No description provided for @scannerStatusAlreadyUsed.
  ///
  /// In de, this message translates to:
  /// **'BEREITS GENUTZT'**
  String get scannerStatusAlreadyUsed;

  /// No description provided for @scannerStatusVoid.
  ///
  /// In de, this message translates to:
  /// **'UNGÜLTIG'**
  String get scannerStatusVoid;

  /// No description provided for @scannerStatusNotFound.
  ///
  /// In de, this message translates to:
  /// **'UNBEKANNT'**
  String get scannerStatusNotFound;

  /// No description provided for @scannerStatusNetworkError.
  ///
  /// In de, this message translates to:
  /// **'KEIN NETZ'**
  String get scannerStatusNetworkError;

  /// No description provided for @scannerStatusUnknown.
  ///
  /// In de, this message translates to:
  /// **'FEHLER'**
  String get scannerStatusUnknown;

  /// No description provided for @offlineMenuPrepare.
  ///
  /// In de, this message translates to:
  /// **'Offline-Modus vorbereiten'**
  String get offlineMenuPrepare;

  /// No description provided for @offlineMenuEnter.
  ///
  /// In de, this message translates to:
  /// **'Offline-Modus starten'**
  String get offlineMenuEnter;

  /// No description provided for @offlineMenuExit.
  ///
  /// In de, this message translates to:
  /// **'Offline-Modus verlassen'**
  String get offlineMenuExit;

  /// No description provided for @offlineMenuReconcile.
  ///
  /// In de, this message translates to:
  /// **'Abgleichen ({count})'**
  String offlineMenuReconcile(int count);

  /// No description provided for @offlineBannerStatus.
  ///
  /// In de, this message translates to:
  /// **'OFFLINE – {count} Scans in Warteschlange'**
  String offlineBannerStatus(int count);

  /// No description provided for @offlineBannerManifest.
  ///
  /// In de, this message translates to:
  /// **'Manifest: {datetime}'**
  String offlineBannerManifest(String datetime);

  /// No description provided for @offlineBannerReconcile.
  ///
  /// In de, this message translates to:
  /// **'Abgleichen'**
  String get offlineBannerReconcile;

  /// No description provided for @offlineSnackManifestLoaded.
  ///
  /// In de, this message translates to:
  /// **'Offline-Manifest geladen: {count} Tickets'**
  String offlineSnackManifestLoaded(int count);

  /// No description provided for @offlineSnackSyncFailed.
  ///
  /// In de, this message translates to:
  /// **'Sync fehlgeschlagen: {error}'**
  String offlineSnackSyncFailed(String error);

  /// No description provided for @offlineSnackReconcileFailed.
  ///
  /// In de, this message translates to:
  /// **'Abgleich fehlgeschlagen: {error}'**
  String offlineSnackReconcileFailed(String error);

  /// No description provided for @reconcileTitle.
  ///
  /// In de, this message translates to:
  /// **'Abgleich abgeschlossen'**
  String get reconcileTitle;

  /// No description provided for @reconcileSummary.
  ///
  /// In de, this message translates to:
  /// **'{accepted} übernommen · {conflicts} Konflikt(e)'**
  String reconcileSummary(int accepted, int conflicts);

  /// No description provided for @reconcileNoConflicts.
  ///
  /// In de, this message translates to:
  /// **'Keine Konflikte — alle Offline-Scans übernommen.'**
  String get reconcileNoConflicts;

  /// No description provided for @reconcileConflictTicket.
  ///
  /// In de, this message translates to:
  /// **'Ticket {code}'**
  String reconcileConflictTicket(String code);

  /// No description provided for @reconcileConflictDevices.
  ///
  /// In de, this message translates to:
  /// **'Gerät {deviceA} {timeA} / Gerät {deviceB}'**
  String reconcileConflictDevices(String deviceA, String timeA, String deviceB);

  /// No description provided for @reconcileReasonAlreadyUsed.
  ///
  /// In de, this message translates to:
  /// **'Doppel-Scan'**
  String get reconcileReasonAlreadyUsed;

  /// No description provided for @reconcileReasonNotEligible.
  ///
  /// In de, this message translates to:
  /// **'Ticket nicht gültig'**
  String get reconcileReasonNotEligible;

  /// No description provided for @reconcileReasonUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekanntes Ticket'**
  String get reconcileReasonUnknown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
