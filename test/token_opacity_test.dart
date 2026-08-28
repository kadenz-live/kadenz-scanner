import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/services/offline_validator.dart';

/// kadenz#1827 — the server signs QR tokens from a keyring and stamps the key
/// id into the signed payload (an optional `k` claim, omitted for key 1). This
/// app must keep working across that change without knowing anything about it,
/// because it treats the token as an opaque string in both paths: online it
/// forwards it verbatim, offline it SHA-256s the whole thing.
///
/// These are regression tests for that contract, not for the server's crypto.
/// They exist so that a future "optimisation" which parses the token
/// client-side — to read the event id, to pre-filter a scan, to label the UI —
/// fails here rather than at a door during a live event.
///
/// The fixtures are real tokens produced by `Tickets::Signer` for the same
/// ticket: one signed with key 1 (no `k`), one signed with key 2 (`k: 2`).
const legacyToken =
    'eyJ0aWQiOiI2ZjFhNWIyYy0wZDNlLTRmNTYtOGE5MC0xYjJjM2Q0ZTVmNjAiLCJlaWQiOiIxYzJkM2U0Zi01YTZiLTRjN2QtOGU5Zi0wYTFiMmMzZDRlNWYiLCJ2IjoxfQ'
    '.uOe-t4jIGg6iYbh_uQswDzPkYUruXncbyBVYIxlHor4';

const rotatedToken =
    'eyJ0aWQiOiI2ZjFhNWIyYy0wZDNlLTRmNTYtOGE5MC0xYjJjM2Q0ZTVmNjAiLCJlaWQiOiIxYzJkM2U0Zi01YTZiLTRjN2QtOGU5Zi0wYTFiMmMzZDRlNWYiLCJ2IjoxLCJrIjoyfQ'
    '.nQcjxe2gazvJdwPIzeBEKVuHUX3wZEanEvIkUiFTabo';

/// Digests as the server computes them (`Scanning::Manifest.digest_for`).
const legacyDigest =
    'cf7cc50b1035181c79f27c285e670935905ed95d567dcafd2f8cd6d27a767c52';
const rotatedDigest =
    '4823598d2b8a05e69849ced415b05f3c52e3ffd8869376ebec6e3b0b22bd2152';

OfflineManifest manifestOf(List<ManifestEntry> entries) => OfflineManifest(
      eventId: '1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f',
      eventTitle: 'Concert',
      generatedAt: DateTime.utc(2030, 1, 1, 18),
      entries: entries,
      validUntil: DateTime.utc(2030, 1, 2, 6),
    );

ManifestEntry entry(String digest, {required String id, String status = 'active'}) =>
    ManifestEntry(id: id, digest: digest, status: status);

/// Fixed clock, inside the manifest's validity window.
DateTime clock() => DateTime.utc(2030, 1, 1, 20);

void main() {
  group('digestOf agrees with the server for both token shapes', () {
    test('a pre-#1827 token (no key id)', () {
      expect(OfflineManifest.digestOf(legacyToken), legacyDigest);
    });

    test('a rotated token carrying a key id', () {
      expect(OfflineManifest.digestOf(rotatedToken), rotatedDigest);
    });

    test('the two shapes are distinguishable — the key id is inside the hash', () {
      expect(legacyDigest, isNot(rotatedDigest));
    });
  });

  group('OfflineValidator is indifferent to the token shape', () {
    test('admits a rotated token exactly like a legacy one', () {
      final v = OfflineValidator(
        manifestOf([entry(rotatedDigest, id: 't-rotated')]),
        clock: clock,
      );

      final outcome = v.validate(rotatedToken);
      expect(outcome.result.ok, true);
      expect(outcome.acceptedTicketId, 't-rotated');
    });

    test('admits both shapes from one manifest — the rotation window case', () {
      // An event that sold tickets on both sides of a key rotation. Every
      // token in the wild has to keep opening the door.
      final v = OfflineValidator(
        manifestOf([
          entry(legacyDigest, id: 't-legacy'),
          entry(rotatedDigest, id: 't-rotated'),
        ]),
        clock: clock,
      );

      expect(v.validate(legacyToken).acceptedTicketId, 't-legacy');
      expect(v.validate(rotatedToken).acceptedTicketId, 't-rotated');
    });

    test('rejects a rotated token that is not in the manifest', () {
      final v = OfflineValidator(
        manifestOf([entry(legacyDigest, id: 't-legacy')]),
        clock: clock,
      );

      final outcome = v.validate(rotatedToken);
      expect(outcome.result.ok, false);
      expect(outcome.result.status, 'not_found');
    });

    test('rejects a token whose key id was edited after signing', () {
      // Tampering anywhere in the token changes its digest, so the manifest
      // stops matching — the device does not need to check the signature to
      // refuse this, and must not start trying to.
      final tampered = legacyToken.replaceFirst('eyJ0aWQ', 'eyJ0aUQ');
      final v = OfflineValidator(
        manifestOf([entry(legacyDigest, id: 't-legacy')]),
        clock: clock,
      );

      expect(v.validate(tampered).result.status, 'not_found');
    });

    test('honours manifest status regardless of which key signed the token', () {
      final v = OfflineValidator(
        manifestOf([entry(rotatedDigest, id: 't-rotated', status: 'void')]),
        clock: clock,
      );

      final outcome = v.validate(rotatedToken);
      expect(outcome.result.ok, false);
      expect(outcome.result.status, 'void');
    });
  });

  group('the app never reads the inside of a token', () {
    test('a token that is not base64/JSON at all still validates by digest', () {
      // If any code path had started decoding the payload, this would throw
      // rather than admit. The device only ever hashes.
      const opaque = 'not-base64-at-all!!.nor-is-this';
      final v = OfflineValidator(
        manifestOf([entry(OfflineManifest.digestOf(opaque), id: 't-opaque')]),
        clock: clock,
      );

      expect(v.validate(opaque).acceptedTicketId, 't-opaque');
    });

    test('ticket identity comes from the manifest entry, not from the payload', () {
      // The token's own `tid` claim says 6f1a5b2c-…; the manifest says
      // 't-from-manifest'. The manifest is what the device reports, which is
      // what keeps the client free of the payload format.
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(legacyToken.split('.').first))),
      ) as Map<String, dynamic>;
      expect(claims['tid'], '6f1a5b2c-0d3e-4f56-8a90-1b2c3d4e5f60');

      final v = OfflineValidator(
        manifestOf([entry(legacyDigest, id: 't-from-manifest')]),
        clock: clock,
      );

      // One call only: a second scan of the same ticket would legitimately be
      // rejected as already-used, which would make the assertion below pass
      // for the wrong reason.
      final accepted = v.validate(legacyToken).acceptedTicketId;
      expect(accepted, 't-from-manifest');
      expect(accepted, isNot(claims['tid']));
    });
  });
}
