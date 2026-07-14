import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/offline_manifest.dart';
import '../models/queued_scan.dart';
import '../models/reconcile_result.dart';
import '../models/scanner_event.dart';
import '../models/validation_result.dart';
import 'auth_service.dart';

class ApiService {
  ApiService(this._auth);
  final AuthService _auth;

  Future<List<ScannerEvent>> events() async {
    final url = Uri.parse('${await _auth.baseUrl()}/api/v1/scanner/events');
    final res = await http.get(url, headers: await _headers());
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['events'] as List).cast<Map<String, dynamic>>();
    return list.map(ScannerEvent.fromJson).toList();
  }

  Future<ValidationResult> validate({required String payload, String? eventId}) async {
    final url = Uri.parse('${await _auth.baseUrl()}/api/v1/scanner/tickets/validate');
    final res = await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'payload': payload,
        if (eventId != null) 'event_id': eventId,
      }),
    );
    return parseValidation(res);
  }

  /// Manual-entry validation: door operator types the printed `TIX-XXXXXXXX`
  /// code when the camera scan won't work. Backend resolves the code to a
  /// ticket and runs the same `Scanning::Validator` path as a camera scan.
  /// Requires a concrete [eventId] — there is no per-tenant code lookup.
  Future<ValidationResult> validateByCode({required String eventId, required String code}) async {
    final url = Uri.parse(
        '${await _auth.baseUrl()}/api/v1/scanner/events/$eventId/validate_code');
    final res = await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'code': code}),
    );
    return parseValidation(res);
  }

  /// Parse a validate/validate_code response into a [ValidationResult] that
  /// is safe for a door decision.
  ///
  /// Fail-safe rule: an admit (`ok: true`) is only ever produced from a real
  /// 2xx response carrying a well-formed JSON object. Any non-2xx status, any
  /// non-JSON / non-object body, or a JSON error object is forced to an
  /// explicit REJECTION. The admit decision must never rest solely on an
  /// optional `ok` key surviving an envelope change: a 2xx with an empty or
  /// garbled body is a reject, not a silent admit.
  @visibleForTesting
  static ValidationResult parseValidation(http.Response res) {
    final ok2xx = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok2xx) {
      return ValidationResult(
        ok: false,
        status: 'server_error',
        message: 'Serverfehler ${res.statusCode} – nicht einlassen',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      return ValidationResult(
        ok: false,
        status: 'server_error',
        message: 'Ungültige Serverantwort – nicht einlassen',
      );
    }
    return ValidationResult.fromJson(decoded);
  }

  /// Pre-sync the offline manifest for an event. The signing secret stays
  /// server-side: the manifest carries SHA-256 digests, not the secret.
  Future<OfflineManifest> manifest(String eventId) async {
    final url = Uri.parse('${await _auth.baseUrl()}/api/v1/scanner/events/$eventId/manifest');
    final res = await http.get(url, headers: await _headers());
    _ensureOk(res);
    return OfflineManifest.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Push the offline scan queue back to the server for reconciliation.
  Future<ReconcileResult> reconcile(String eventId, List<QueuedScan> scans) async {
    final url = Uri.parse('${await _auth.baseUrl()}/api/v1/scanner/events/$eventId/reconcile');
    final res = await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'scans': scans.map((s) => s.toJson()).toList()}),
    );
    _ensureOk(res);
    return ReconcileResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Marker so the API's OriginGuard knows this is a native (non-browser)
  /// client and can safely skip the Origin/Referer check. The API only
  /// inspects the header's presence; the value is logged for forensic
  /// correlation and follows `mobile-<semver>` by convention.
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
      throw Exception('Request failed: ${res.statusCode}');
    }
  }
}
