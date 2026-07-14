import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Apple App Attest / Google Play Integrity client glue (issue #905, ADR-0034 /
/// ADR-0039 §B).
///
/// Scope of this class: the **byte-for-byte hash contract** between this client
/// and the Rails verifier (`Attestation::AppleVerifier` /
/// `Attestation::GoogleVerifier`), plus the challenge fetch and verification
/// POST. The native key generation + `DCAppAttestService.attestKey` /
/// `PlayIntegrity` calls are made over a platform channel by the caller, which
/// passes [computeClientDataHash]'s result (iOS) or the raw nonce (Android)
/// down to the OS API.
///
/// ## clientDataHash contract (the load-bearing invariant)
///
/// The server issues the challenge as a Base64 *string*
/// (`SecureRandom.base64(32)`), stores it verbatim, and on verification hands
/// that exact string to the `devicecheck` gem, which computes:
///
/// ```ruby
/// clientDataHash = OpenSSL::Digest::SHA256.digest(challenge)
/// ```
///
/// i.e. SHA-256 over the **raw bytes of the Base64 challenge string** — it is
/// NOT Base64-decoded first, and the app / bundle id is NOT concatenated (the
/// app is bound separately via `rp_id_hash == SHA-256(app_id)` inside the
/// authenticator data). The earlier ADR-0039 draft wrongly specified
/// `SHA-256(nonce + bundle_id)`; that was corrected server-side and is now
/// guarded by an unstubbed fixture spec. This client must mirror the corrected
/// formula exactly or every legitimate iOS attestation raises
/// `Failed challenge check`.
///
/// Apple's `DCAppAttestService.attestKey(_:clientDataHash:completionHandler:)`
/// expects the *digest bytes* (a 32-byte `Data`), so [computeClientDataHash]
/// returns the raw SHA-256 digest as a `List<int>` rather than a hex string.
class AttestationService {
  AttestationService(this._auth, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final AuthService _auth;
  final http.Client _http;

  /// Compute the Apple App Attest `clientDataHash` for [challenge].
  ///
  /// [challenge] is the **exact** Base64 nonce string returned by
  /// `POST /api/v1/scanner/attestation_challenges`. It is hashed byte-for-byte
  /// as received (its UTF-8 bytes); it is NOT Base64-decoded and the bundle /
  /// app id is NOT concatenated. The result is the raw 32-byte SHA-256 digest,
  /// matching `OpenSSL::Digest::SHA256.digest(challenge)` server-side and ready
  /// to hand to `DCAppAttestService.attestKey(keyId:clientDataHash:)`.
  static List<int> computeClientDataHash(String challenge) =>
      sha256.convert(utf8.encode(challenge)).bytes;

  /// Fetch a fresh attestation challenge for this device.
  ///
  /// Returns the Base64 nonce string verbatim — pass it unchanged to
  /// [computeClientDataHash] (iOS) or as the Play Integrity request hash
  /// (Android), and echo it back as `nonce` on [submitVerification].
  Future<String> fetchChallenge({required String platform}) async {
    final url = Uri.parse(
        '${await _auth.baseUrl()}/api/v1/scanner/attestation_challenges');
    final res = await _http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'device_id': await _auth.deviceId(),
        'platform': platform,
      }),
    );
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['nonce'] as String;
  }

  /// Submit the platform attestation for server verification.
  ///
  /// [nonce] must be the exact challenge string returned by [fetchChallenge].
  /// [attestationToken] is the Base64 Apple attestation object or the Play
  /// Integrity verdict JWT. [keyId] is required for iOS (the
  /// `DCAppAttestService.generateKey` identifier) and omitted for Android.
  Future<DateTime> submitVerification({
    required String platform,
    required String nonce,
    required String attestationToken,
    String? keyId,
  }) async {
    final url = Uri.parse(
        '${await _auth.baseUrl()}/api/v1/scanner/attestation_verifications');
    final res = await _http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'device_id': await _auth.deviceId(),
        'platform': platform,
        'nonce': nonce,
        'attestation_token': attestationToken,
        if (keyId != null) 'key_id': keyId,
      }),
    );
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime.parse(body['attested_until'] as String);
  }

  /// Device-scoping headers for the manifest / scan endpoints so the
  /// (device_id, platform) attestation gate (S-06) can match the verified
  /// attestation row to the requesting device.
  Future<Map<String, String>> attestationHeaders(
      {required String platform}) async {
    return {
      'X-Device-Id': await _auth.deviceId(),
      'X-Device-Platform': platform,
    };
  }

  static const String _kClientHeaderName = 'X-Kadenz-Client';
  static const String _kClientHeaderValue = 'mobile-scanner/1.8.2';

  Future<Map<String, String>> _headers() async {
    final token = await _auth.token();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      _kClientHeaderName: _kClientHeaderValue,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Attestation request failed: ${res.statusCode}');
    }
  }
}
