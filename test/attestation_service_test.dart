import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/services/attestation_service.dart';

void main() {
  // The exact contract guarded server-side by the unstubbed
  // `Attestation::AppleVerifier` fixture spec (issue #905, ADR-0039 §B):
  //
  //   clientDataHash = OpenSSL::Digest::SHA256.digest(challenge)
  //
  // where `challenge` is the Base64 nonce string issued verbatim by
  // `POST /api/v1/scanner/attestation_challenges`. No Base64-decode, no
  // bundle-id concatenation.
  group('AttestationService.computeClientDataHash', () {
    // A representative server challenge: valid Base64 of 32 bytes, matching
    // `SecureRandom.base64(32)`.
    const challenge = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw=';
    const bundleId = 'live.kadenz.scanner';

    test('equals SHA-256 of the exact challenge bytes (no concatenation)', () {
      final expected = sha256.convert(utf8.encode(challenge)).bytes;

      expect(
        AttestationService.computeClientDataHash(challenge),
        equals(expected),
      );
    });

    test('returns the raw 32-byte digest (Apple expects Data, not hex)', () {
      final hash = AttestationService.computeClientDataHash(challenge);

      expect(hash.length, 32);
      // Every element is a byte, not a hex character.
      expect(hash.every((b) => b >= 0 && b <= 255), isTrue);
    });

    test('does NOT concatenate the bundle id (the old, wrong ADR formula)', () {
      final wrong = sha256.convert(utf8.encode(challenge + bundleId)).bytes;

      expect(
        AttestationService.computeClientDataHash(challenge),
        isNot(equals(wrong)),
      );
    });

    test('does NOT base64-decode the challenge before hashing', () {
      // The server hashes the Base64 *string* bytes, not the decoded nonce.
      final decodedThenHashed =
          sha256.convert(base64.decode(challenge)).bytes;

      expect(
        AttestationService.computeClientDataHash(challenge),
        isNot(equals(decodedThenHashed)),
      );
    });

    test('is deterministic for the same challenge', () {
      expect(
        AttestationService.computeClientDataHash(challenge),
        equals(AttestationService.computeClientDataHash(challenge)),
      );
    });

    test('differs for a different challenge', () {
      const other = 'ZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmY=';

      expect(
        AttestationService.computeClientDataHash(challenge),
        isNot(equals(AttestationService.computeClientDataHash(other))),
      );
    });
  });
}
