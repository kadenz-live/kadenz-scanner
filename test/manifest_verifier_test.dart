import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/models/offline_manifest.dart';
import 'package:kadenz_scanner/security/manifest_signing_keys.dart';
import 'package:kadenz_scanner/services/manifest_verifier.dart';

import 'support/manifest_fixtures.dart';

void main() {
  late ManifestFixtures fixtures;
  late ManifestVerifier verifier;

  setUp(() async {
    fixtures = await ManifestFixtures.create();
    verifier = ManifestVerifier(publicKeys: fixtures.pinnedKeys);
  });

  Future<ManifestVerification> check(String raw, {bool ratchet = false}) =>
      verifier.verify(raw, hasSeenSignedManifest: ratchet);

  group('a verified manifest', () {
    test('is accepted and marked signed', () async {
      final result = await check(await fixtures.signed());

      expect(result.accepted, isTrue);
      expect(result.verified, isTrue);
      expect(result.manifest!.trust, ManifestTrust.signed);
      expect(result.signingKeyId, fixtures.kid);
    });

    test('is read from the signed payload, not from the plain top-level body', () async {
      // The plain fields say the manifest is valid for another century and that
      // a third ticket is admissible. The signed payload says otherwise. Only
      // the signed payload may be believed.
      final signed = await fixtures.signed();
      final body = jsonDecode(signed) as Map<String, dynamic>;
      final lying = jsonEncode({
        ...body,
        'valid_until': '2999-01-01T00:00:00.000Z',
        'tickets': [
          ...(body['tickets'] as List),
          {'id': 'smuggled', 'digest': 'c' * 64, 'status': 'active'},
        ],
      });

      final result = await check(lying);

      expect(result.verified, isTrue);
      expect(result.manifest!.validUntil, DateTime.utc(2030, 1, 2, 6));
      expect(result.manifest!.entries.map((e) => e.id), ['t1', 't2']);
    });

    test('carries valid_until, event_state and manifest_version off the signed document', () async {
      final result = await check(await fixtures.signed());

      expect(result.manifest!.validUntil, DateTime.utc(2030, 1, 2, 6));
      expect(result.manifest!.eventState, 'open');
      expect(result.manifest!.manifestVersion, 3);
    });
  });

  group('tampering — each mutation must be refused', () {
    test('control: the untampered document verifies', () async {
      expect((await check(await fixtures.signed())).verified, isTrue);
    });

    test('an extended valid_until is refused', () async {
      // The sharp end: since kadenz#1778 the scanner honours a server-supplied
      // expiry over its own 12h constant, so this field decides whether the
      // door keeps working.
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) => {...doc, 'valid_until': '2999-01-01T00:00:00.000Z'},
      );

      final result = await check(tampered);

      expect(result.accepted, isFalse);
      expect(result.rejection, ManifestRejection.signatureInvalid);
    });

    test('a shortened valid_until is refused too — tampering is not only about admitting', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) => {...doc, 'valid_until': '2000-01-01T00:00:00.000Z'},
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });

    test('an added entry in the admissible set is refused', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) => {
          ...doc,
          'tickets': [
            ...(doc['tickets'] as List),
            {'id': 'smuggled', 'digest': 'c' * 64, 'status': 'active'},
          ],
        },
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });

    test('a void entry flipped back to active is refused', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) {
          final tickets = (doc['tickets'] as List).cast<Map<String, dynamic>>();
          return {
            ...doc,
            'tickets': tickets.map((t) => t['id'] == 't2' ? {...t, 'status': 'active'} : t).toList(),
          };
        },
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });

    test('a removed entry is refused', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) => {...doc, 'tickets': const <Map<String, dynamic>>[]},
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });

    test('an event_state edited away from cancelled is refused', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(doc: ManifestFixtures.document(eventState: 'cancelled')),
        (doc) => {...doc, 'event_state': 'open'},
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });

    test('a swapped key id is refused, because kid is inside the signing input', () async {
      final signed = await fixtures.signed();
      final body = jsonDecode(signed) as Map<String, dynamic>;
      final envelope = Map<String, dynamic>.from(body['signature'] as Map<String, dynamic>);
      // Point the envelope at a *different* pinned key holding the same
      // material, so "unknown key" cannot be the reason it fails.
      final swapped = jsonEncode({...body, 'signature': {...envelope, 'kid': 'other'}});
      final twoKeyVerifier = ManifestVerifier(
        publicKeys: {...fixtures.pinnedKeys, 'other': fixtures.publicKeyB64},
      );

      final result = await twoKeyVerifier.verify(swapped, hasSeenSignedManifest: true);

      expect(result.rejection, ManifestRejection.signatureInvalid);
    });

    test('a corrupted signature is refused', () async {
      final signed = await fixtures.signed();
      final body = jsonDecode(signed) as Map<String, dynamic>;
      final envelope = Map<String, dynamic>.from(body['signature'] as Map<String, dynamic>);
      final sig = envelope['sig'] as String;
      envelope['sig'] = '${sig.substring(0, sig.length - 2)}${sig.endsWith('AA') ? 'BB' : 'AA'}';

      final result = await check(jsonEncode({...body, 'signature': envelope}));

      expect(result.rejection, ManifestRejection.signatureInvalid);
    });

    test('a signature made by another key is refused', () async {
      final other = await ManifestFixtures.create();
      final signedByOther = await other.signed(overrideKid: fixtures.kid);

      expect((await check(signedByOther)).rejection, ManifestRejection.signatureInvalid);
    });

    test('a signed payload that is not JSON is refused', () async {
      final doc = ManifestFixtures.document();
      final signed = await fixtures.signed(doc: doc);
      final body = jsonDecode(signed) as Map<String, dynamic>;
      final envelope = Map<String, dynamic>.from(body['signature'] as Map<String, dynamic>);
      envelope['payload'] = base64Url.encode(utf8.encode('not json')).replaceAll('=', '');

      expect((await check(jsonEncode({...body, 'signature': envelope}))).rejection,
          ManifestRejection.signatureInvalid);
    });
  });

  group('rollout policy — the transition table in ADR-0055 §C', () {
    test('an unsigned manifest is accepted while the ratchet is open', () async {
      // A new scanner talking to an API that has not had its key provisioned.
      // Refusing here would take the door down for a rollout ordering problem.
      final result = await check(ManifestFixtures.unsigned());

      expect(result.accepted, isTrue);
      expect(result.verified, isFalse);
      expect(result.manifest!.trust, ManifestTrust.unsigned);
    });

    test('an unsigned manifest is refused once the ratchet has closed', () async {
      // Without this, "tolerate unsigned during rollout" is a permanent
      // downgrade available to anyone who can strip one field.
      final result = await check(ManifestFixtures.unsigned(), ratchet: true);

      expect(result.accepted, isFalse);
      expect(result.rejection, ManifestRejection.signatureMissing);
    });

    test('stripping the signature off a signed manifest is refused after the ratchet', () async {
      final stripped = ManifestFixtures.stripSignature(await fixtures.signed());

      expect((await check(stripped, ratchet: true)).rejection, ManifestRejection.signatureMissing);
    });

    test('an unknown key is tolerated while the ratchet is open, not treated as tampering', () async {
      // This is what makes rollout ordering forgiving: a server that starts
      // signing before the pinning release lands does not brick anything.
      final other = await ManifestFixtures.create();

      final result = await check(await other.signed());

      expect(result.accepted, isTrue);
      expect(result.verified, isFalse);
    });

    test('an unknown key is refused once the ratchet has closed', () async {
      final other = await ManifestFixtures.create();

      expect((await check(await other.signed(), ratchet: true)).rejection,
          ManifestRejection.signatureUnknownKey);
    });

    test('an unsupported envelope version is treated as unknown, not as tampering', () async {
      final future = await fixtures.signed(envelopeVersion: 2);

      expect((await check(future)).accepted, isTrue);
      expect((await check(future, ratchet: true)).rejection, ManifestRejection.signatureUnknownKey);
    });

    test('an unsupported algorithm is treated as unknown, not as tampering', () async {
      final future = await fixtures.signed(algorithm: 'ml-dsa-44');

      expect((await check(future)).accepted, isTrue);
      expect((await check(future, ratchet: true)).rejection, ManifestRejection.signatureUnknownKey);
    });

    test('requireSignature refuses everything unverified regardless of the ratchet', () async {
      final strict = ManifestVerifier(publicKeys: fixtures.pinnedKeys, requireSignature: true);

      expect((await strict.verify(ManifestFixtures.unsigned(), hasSeenSignedManifest: false)).rejection,
          ManifestRejection.signatureMissing);
      expect((await strict.verify(await fixtures.signed(), hasSeenSignedManifest: false)).verified, isTrue);
    });

    test('a tampered payload is refused even with the ratchet open — that branch is never soft', () async {
      final tampered = ManifestFixtures.tamperPayload(
        await fixtures.signed(),
        (doc) => {...doc, 'valid_until': '2999-01-01T00:00:00.000Z'},
      );

      expect((await check(tampered)).rejection, ManifestRejection.signatureInvalid);
    });
  });

  group('malformed input', () {
    test('a body that is not JSON is refused', () async {
      expect((await check('<html>504 Gateway Timeout</html>')).rejection, ManifestRejection.malformed);
    });

    test('a JSON body that is not a manifest is refused', () async {
      expect((await check('{"error":"attestation_required"}')).rejection, ManifestRejection.malformed);
    });

    test('a signature field of the wrong type does not crash', () async {
      final body = jsonDecode(ManifestFixtures.unsigned()) as Map<String, dynamic>;

      final result = await check(jsonEncode({...body, 'signature': 'nope'}));

      expect(result.accepted, isTrue);
      expect(result.verified, isFalse);
    });
  });

  group('cross-language wire compatibility', () {
    // The one test no Dart-signs-Dart fixture can give: the Ruby signer in the
    // API repo and this verifier must agree byte for byte, including base64url
    // without padding and non-ASCII event titles.
    late ManifestVerifier rubyVerifier;

    setUp(() {
      rubyVerifier = ManifestVerifier(publicKeys: {
        ManifestFixtures.rubyFixtureKid: ManifestFixtures.rubyFixturePublicKey,
      });
    });

    test('verifies a manifest signed by Scanning::ManifestSigner', () async {
      final result = await rubyVerifier.verify(
        ManifestFixtures.rubySignedFixture(),
        hasSeenSignedManifest: true,
      );

      expect(result.verified, isTrue);
      expect(result.signingKeyId, ManifestFixtures.rubyFixtureKid);
      expect(result.manifest!.eventId, 'evt-ruby-fixture');
      expect(result.manifest!.validUntil, DateTime.utc(2030, 1, 2, 6));
      expect(result.manifest!.entries.length, 2);
    });

    test('survives a non-ASCII event title, so utf8 handling matches on both sides', () async {
      final result = await rubyVerifier.verify(
        ManifestFixtures.rubySignedFixture(),
        hasSeenSignedManifest: true,
      );

      expect(result.manifest!.eventTitle, 'Kadenz Nacht — Öl & Ünïcode');
    });

    test('rejects the Ruby fixture once a byte of its payload changes', () async {
      final tampered = ManifestFixtures.tamperPayload(
        ManifestFixtures.rubySignedFixture(),
        (doc) => {...doc, 'valid_until': '2999-01-01T00:00:00Z'},
      );

      expect((await rubyVerifier.verify(tampered, hasSeenSignedManifest: false)).rejection,
          ManifestRejection.signatureInvalid);
    });
  });

  group('pinned keyring', () {
    test('a release build does not accept the development keypair', () async {
      // The development private key is committed in the API repo. It must not
      // be able to admit anyone through a real door.
      final release = manifestSigningPublicKeys(debug: false, fromBuild: '');

      expect(release.containsKey('1e094ef6'), isFalse);
    });

    test('a debug build does accept it, so the signed path is what CI exercises', () {
      final debug = manifestSigningPublicKeys(debug: true, fromBuild: '');

      expect(debug['1e094ef6'], ManifestFixtures.rubyFixturePublicKey);
    });

    test('a build-time define adds keys without replacing the pinned ones', () {
      final keys = manifestSigningPublicKeys(debug: true, fromBuild: 'abc12345:AAAA,def67890:BBBB');

      expect(keys['abc12345'], 'AAAA');
      expect(keys['def67890'], 'BBBB');
      expect(keys.containsKey('1e094ef6'), isTrue);
    });

    test('a malformed define costs coverage but does not throw', () {
      expect(parseManifestSigningKeys('garbage,:novalue,nokey:,ok:VALUE'), {'ok': 'VALUE'});
    });
  });
}
