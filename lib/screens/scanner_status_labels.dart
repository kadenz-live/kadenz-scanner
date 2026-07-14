import '../l10n/app_localizations.dart';
import '../models/validation_result.dart';

/// Returns the door-staff facing, locale-aware label for a [ValidationResult].
///
/// The backend (and the offline validator) returns status codes as snake_case
/// machine strings (`already_used`, `not_found`, `network_error`, …). Door
/// staff in a loud venue need a short, glanceable upper-case label — never a
/// raw enum. Unknown statuses fall through to `scannerStatusUnknown` so a
/// freshly-introduced server-side status code still surfaces a deliberate
/// "ERROR / FEHLER" rather than crashing.
String scannerStatusLabel(ValidationResult r, AppLocalizations l) {
  if (r.ok) return l.scannerStatusOk;
  switch (r.status) {
    case 'already_used':
      return l.scannerStatusAlreadyUsed;
    case 'void':
      return l.scannerStatusVoid;
    case 'not_found':
      return l.scannerStatusNotFound;
    case 'network_error':
      return l.scannerStatusNetworkError;
    default:
      return l.scannerStatusUnknown;
  }
}
