import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/scanner_user.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Where the resolved API base URL came from. Surfaced in the settings screen
/// so door staff can debug a "scanner can't reach the server" situation
/// without us having to walk them through it on the phone.
enum ApiUrlSource {
  /// Injected at build time via `flutter run --dart-define=KADENZ_API=...`
  /// or `flutter build ... --dart-define=KADENZ_API=...`. Wins over any
  /// stored value so production builds cannot be redirected from a stale
  /// secure-storage entry left over from a previous install.
  buildEnv,

  /// Set by the user in the settings screen, persisted to flutter_secure_storage.
  storedOverride,

  /// Compiled-in fallback (`https://kadenz.live`).
  defaultProd,
}

class ResolvedApiUrl {
  const ResolvedApiUrl(this.url, this.source);
  final String url;
  final ApiUrlSource source;
}

class AuthService {
  AuthService({FlutterSecureStorage? storage, http.Client? httpClient})
      : _storage = storage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';
  static const _kBaseUrl = 'api_base_url';
  static const _kDeviceId = 'device_id';

  /// Compile-time API URL injected via `--dart-define=KADENZ_API=...`.
  /// Empty string means "not set" (the `String.fromEnvironment` default).
  static const String _buildEnvApiUrl =
      String.fromEnvironment('KADENZ_API', defaultValue: '');

  /// Fallback when nothing else is set. Production hostname over HTTPS so a
  /// fresh install on a real device just works; only local dev needs an
  /// override.
  static const String defaultApiUrl = 'https://kadenz.live';

  final FlutterSecureStorage _storage;
  final http.Client _http;

  /// Resolve the API base URL using the documented precedence:
  ///
  /// 1. `String.fromEnvironment('KADENZ_API')` — compile-time, wins.
  /// 2. Stored override from the settings screen.
  /// 3. [defaultApiUrl] (`https://kadenz.live`).
  Future<ResolvedApiUrl> resolveBaseUrl() async {
    if (_buildEnvApiUrl.isNotEmpty) {
      return const ResolvedApiUrl(_buildEnvApiUrl, ApiUrlSource.buildEnv);
    }
    final stored = await _storage.read(key: _kBaseUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      return ResolvedApiUrl(stored.trim(), ApiUrlSource.storedOverride);
    }
    return const ResolvedApiUrl(defaultApiUrl, ApiUrlSource.defaultProd);
  }

  /// Convenience for callers that only need the URL string. Keeps the rest
  /// of the codebase ergonomic.
  Future<String> baseUrl() async => (await resolveBaseUrl()).url;

  /// Persist a user-entered override. No-op-style: a build-env URL still
  /// wins on the next [resolveBaseUrl] call — but we still store the value
  /// so it kicks in if a future build ships without `--dart-define`.
  Future<void> setBaseUrl(String url) =>
      _storage.write(key: _kBaseUrl, value: url.trim());

  /// Clear any stored override so resolution falls back to env / default.
  Future<void> clearStoredBaseUrl() => _storage.delete(key: _kBaseUrl);

  Future<String?> token() => _storage.read(key: _kToken);

  /// Stable per-install device id used to attribute offline scans during
  /// reconcile (so cross-device double-scans can be told apart).
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _kDeviceId);
    if (existing != null) return existing;
    final generated = 'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    await _storage.write(key: _kDeviceId, value: generated);
    return generated;
  }

  Future<ScannerUser?> currentUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null) return null;
    return ScannerUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Lightweight reachability probe against `/healthz`. Returns `true` only on
  /// a 2xx response; any network error, timeout, or non-2xx → `false`. The
  /// login screen uses this to show a "server unreachable" banner instead of
  /// failing silently on the first sign-in attempt.
  Future<bool> isApiReachable({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final url = Uri.parse('${await baseUrl()}/healthz');
      final res = await _http.get(url).timeout(timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Sign in and confirm — with the SERVER, not with a local role table — that
  /// this operator may actually scan something.
  ///
  /// kadenz#1816: this method used to gate on the role string, refusing every
  /// login whose `user.role` was not `'scanner'` or `'admin'`. The server enum
  /// is `{ customer, scanner, global_admin }`, so `'admin'` matched nothing,
  /// a global admin was rejected, and — the part that mattered — a door
  /// operator holding an `einlass` membership on the account whose events they
  /// work was rejected too. The single role that DID pass, `scanner`, was
  /// exactly the one the API short-circuited to platform-wide scan authority.
  /// The client gate was therefore what forced every door device onto
  /// platform-wide authority and left the per-account model unexercised.
  ///
  /// The replacement is deliberately NOT a wider role list. The client does not
  /// model authority at all any more: it asks the API whether this operator can
  /// reach the scanner surface and takes that answer. When the authority model
  /// changes again, no scanner release is required.
  Future<ScannerUser> signIn(String email, String password) async {
    final url = Uri.parse('${await baseUrl()}/api/v1/auth/sign_in');
    final res = await _http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // OriginGuard escape hatch for native (non-browser) clients.
        // See web/api/app/controllers/concerns/origin_guard.rb.
        'X-Kadenz-Client': 'mobile-scanner/1.8.2',
        // kadenz#1816 — bind this device to the session row being minted, so
        // "revoke that phone" becomes an available operation instead of only
        // "revoke that session" (which the device re-establishes on the next
        // login). An API that predates the binding ignores the header.
        'X-Device-Id': await deviceId(),
      },
      body: jsonEncode({'user': {'email': email, 'password': password}}),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw AuthException(_extractError(res) ?? 'Login fehlgeschlagen (${res.statusCode})');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final user = ScannerUser.fromJson(body['user'] as Map<String, dynamic>);

    final token = res.headers['authorization']?.replaceFirst(RegExp(r'^Bearer\s+'), '')
        ?? body['token'] as String?;
    if (token == null) throw AuthException('Kein Token erhalten.');

    // Ask the server. Throws AuthException on a definitive refusal; nothing is
    // persisted in that case, so a refused operator is not left holding a token.
    await _assertScannerAccess(token);

    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    return user;
  }

  /// Server-authoritative scan-access probe against the scanner event list.
  ///
  /// Only an explicit **403** is treated as "this account may not scan": that
  /// is the API's coarse `require_scanner_access!` gate answering the question
  /// we asked. Every other outcome — 5xx, timeout, malformed body, a transport
  /// error — is NOT an authorization answer, and converting it into one would
  /// lock door staff out during a server blip at the worst possible moment. We
  /// let those through: the operator lands in the app and gets the real error
  /// from the very same endpoint, with the retry affordances the event picker
  /// already has.
  ///
  /// Cross-version: this endpoint exists and enforces the same coarse gate on
  /// every API release the scanner has ever talked to, so a new client against
  /// an older API behaves identically.
  Future<void> _assertScannerAccess(String token) async {
    final http.Response res;
    try {
      res = await _http.get(
        Uri.parse('${await baseUrl()}/api/v1/scanner/events'),
        headers: {
          'Accept': 'application/json',
          'X-Kadenz-Client': 'mobile-scanner/1.8.2',
          'X-Device-Id': await deviceId(),
          'Authorization': 'Bearer $token',
        },
      ).timeout(_scanAccessProbeTimeout);
    } catch (_) {
      return;
    }

    if (res.statusCode == 403) {
      throw AuthException(
        'Dieser Account darf keine Tickets scannen. '
        'Die Kontoinhaberin oder der Kontoinhaber muss Dir eine Einlass-Berechtigung '
        'für den jeweiligen Account geben.',
      );
    }
  }

  static const Duration _scanAccessProbeTimeout = Duration(seconds: 8);

  Future<void> signOut() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
  }

  String? _extractError(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map<String, dynamic>) {
        final messages = err['messages'];
        if (messages is List<dynamic>) return messages.join(', ');
        final message = err['message'];
        if (message is String) return message;
      }
    } catch (_) {}
    return null;
  }
}
