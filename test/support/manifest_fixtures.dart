
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Builds manifest documents in the exact wire shape the API serves, so the
/// verifier is tested against the contract rather than against a convenience
/// helper that agrees with it.
class ManifestFixtures {
  ManifestFixtures._(this.keyPair, this.publicKeyB64, this.kid);

  static Future<ManifestFixtures> create({List<int>? seed}) async {
    final algorithm = Ed25519();
    final keyPair = seed == null
        ? await algorithm.newKeyPair()
        : await algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyB64 = base64.encode(publicKey.bytes);
    final digest = await Sha256().hash(publicKey.bytes);
    final kid = _hex(digest.bytes).substring(0, 8);
    return ManifestFixtures._(keyPair, publicKeyB64, kid);
  }

  final SimpleKeyPair keyPair;
  final String publicKeyB64;
  final String kid;

  Map<String, String> get pinnedKeys => {kid: publicKeyB64};

  static Map<String, dynamic> document({
    String eventId = 'evt-1',
    String validUntil = '2030-01-02T06:00:00.000Z',
    String generatedAt = '2030-01-01T18:00:00.000Z',
    String eventState = 'open',
    int manifestVersion = 3,
    List<Map<String, dynamic>>? tickets,
  }) =>
      {
        'event_id': eventId,
        'event_title': 'Concert',
        'manifest_version': manifestVersion,
        'generated_at': generatedAt,
        'valid_until': validUntil,
        'event_state': eventState,
        'tickets': tickets ??
            [
              {'id': 't1', 'digest': 'a' * 64, 'status': 'active'},
              {'id': 't2', 'digest': 'b' * 64, 'status': 'void'},
            ],
      };

  /// A plain, pre-#1823 manifest body: no `signature` key at all.
  static String unsigned([Map<String, dynamic>? doc]) => jsonEncode(doc ?? document());

  /// A signed manifest in the wire shape: the plain fields, plus the envelope.
  Future<String> signed({
    Map<String, dynamic>? doc,
    String? overrideKid,
    int envelopeVersion = 1,
    String algorithm = 'ed25519',
  }) async {
    final body = doc ?? document();
    final payload = _b64url(utf8.encode(jsonEncode(body)));
    final kidInEnvelope = overrideKid ?? kid;
    final signature = await Ed25519().sign(
      utf8.encode('$envelopeVersion.$kidInEnvelope.$payload'),
      keyPair: keyPair,
    );
    return jsonEncode({
      ...body,
      'signature': {
        'alg': algorithm,
        'sv': envelopeVersion,
        'kid': kidInEnvelope,
        'payload': payload,
        'sig': _b64url(signature.bytes),
      },
    });
  }

  /// Replaces the signed payload with an edited document, leaving the original
  /// signature in place — exactly what an attacker with write access to
  /// SharedPreferences would produce.
  static String tamperPayload(String signedDocument, Map<String, dynamic> Function(Map<String, dynamic>) edit) {
    final body = jsonDecode(signedDocument) as Map<String, dynamic>;
    final envelope = Map<String, dynamic>.from(body['signature'] as Map<String, dynamic>);
    final inner = jsonDecode(utf8.decode(_b64urlDecode(envelope['payload'] as String))) as Map<String, dynamic>;
    final edited = edit(inner);
    envelope['payload'] = _b64url(utf8.encode(jsonEncode(edited)));
    return jsonEncode({...edited, 'signature': envelope});
  }

  /// Removes the envelope, leaving a document that looks pre-#1823.
  static String stripSignature(String signedDocument) {
    final body = jsonDecode(signedDocument) as Map<String, dynamic>..remove('signature');
    return jsonEncode(body);
  }

  /// The cross-language fixture: produced by the Ruby signer in the API repo
  /// (`Scanning::ManifestSigner`) with the committed development keypair.
  /// Proves the two implementations agree on the wire format, which no
  /// Dart-signs-Dart test can.
  static String rubySignedFixture() =>
      File('test/support/ruby_signed_manifest.json').readAsStringSync().trim();

  static const String rubyFixtureKid = '1e094ef6';
  static const String rubyFixturePublicKey = '5l8ORBtOj9/hHwSNTd6CbD187hba9nnxbMI6KyVusjA=';

  /// SHA-256 of a QR token, the way the device computes it at the door.
  static String digestOf(String qrToken) =>
      crypto.sha256.convert(utf8.encode(qrToken)).toString();

  static String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _b64urlDecode(String value) =>
      base64Url.decode(value.padRight((value.length + 3) & ~3, '='));

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
