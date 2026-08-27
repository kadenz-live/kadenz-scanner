import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../models/offline_manifest.dart';
import '../security/manifest_signing_keys.dart';

/// Why a manifest was refused. Never a reason to *admit* — only ever a reason
/// to keep the manifest already on the device.
enum ManifestRejection {
  /// Body is not a manifest at all.
  malformed,

  /// Signed by a key we hold, and the signature does not check out. The
  /// document was edited after the server produced it.
  signatureInvalid,

  /// No `signature` at all, on a device that has already verified one.
  signatureMissing,

  /// Signed by a key this build does not hold, on a device that has already
  /// verified one.
  signatureUnknownKey,
}

/// Compile-time policy for the transition (ADR-0055 §C).
class ManifestSignaturePolicy {
  const ManifestSignaturePolicy._();

  /// When true, only a verified manifest is ever accepted.
  ///
  /// `false` for the release that introduces verification, because a hard
  /// reject during rollout takes doors down: a scanner on this build talking to
  /// an API that has not had its signing key provisioned would refuse every
  /// manifest it was ever offered. **A door outage is worse than the finding.**
  ///
  /// The tolerance is not open-ended — it is closed per device by the
  /// ratchet in [ManifestVerifier.verify], which makes unsigned unacceptable
  /// forever after the first successful verification. This flag flips to `true`
  /// one release after the production key is provisioned, to catch the devices
  /// that never came online in between.
  static const bool requireSignature = bool.fromEnvironment(
    'KADENZ_REQUIRE_MANIFEST_SIGNATURE',
    defaultValue: false,
  );
}

/// The outcome of examining one manifest document.
class ManifestVerification {
  const ManifestVerification._({
    this.manifest,
    this.trust,
    this.rejection,
    this.signingKeyId,
  });

  const ManifestVerification.accepted(
    OfflineManifest manifest,
    ManifestTrust trust, {
    String? signingKeyId,
  }) : this._(manifest: manifest, trust: trust, signingKeyId: signingKeyId);

  const ManifestVerification.rejected(ManifestRejection rejection)
      : this._(rejection: rejection);

  /// Non-null only when the manifest may be used.
  final OfflineManifest? manifest;
  final ManifestTrust? trust;
  final ManifestRejection? rejection;

  /// Which pinned key verified this, for diagnostics. Null when unsigned.
  final String? signingKeyId;

  bool get accepted => manifest != null;
  bool get verified => trust == ManifestTrust.signed;
}

/// Verifies the detached Ed25519 envelope on an offline manifest before any of
/// it is trusted (kadenz#1823, ADR-0055).
///
/// ## What the signature buys
///
/// The manifest is the document that decides who gets through a door when the
/// network is gone, and since #1778 it also carries the `valid_until` the
/// scanner honours *over* its own 12-hour constant. Until it was signed, all of
/// that — the admissible set, each entry's status, and the expiry — was
/// plaintext local state in `SharedPreferences` on a device the door staff
/// hold. Verification turns it into a server assertion.
///
/// ## What is verified
///
/// The envelope carries the manifest as opaque bytes
/// (`signature.payload`, base64url) and a signature over
/// `"<sv>.<kid>.<payload>"`. On success this class parses the manifest **from
/// those bytes** and ignores the plain top-level fields entirely — so there is
/// no way for a field to be read from an unsigned copy. Because the signature
/// is over bytes rather than a canonicalised projection, it is not possible for
/// it to cover only part of the document, which is the failure mode that would
/// look like protection while providing none.
///
/// ## The three failure modes, and why they differ
///
/// * **bad signature under a key we hold** — the document was edited. Reject
///   always, at any stage of the rollout.
/// * **key we do not hold** — we cannot judge. Soft: tolerated until this
///   device has verified something.
/// * **no signature at all** — either a pre-#1823 API, or the field was
///   stripped. Indistinguishable on its own, so it is handled by the ratchet:
///   tolerated exactly until this device has verified a manifest once, and
///   refused from then on. Without that one-way ratchet, "tolerate unsigned
///   during rollout" would be a permanent downgrade anyone could take.
class ManifestVerifier {
  ManifestVerifier({
    Map<String, String>? publicKeys,
    this.requireSignature = ManifestSignaturePolicy.requireSignature,
    SignatureAlgorithm? algorithm,
  })  : publicKeys = publicKeys ?? manifestSigningPublicKeys(),
        _algorithm = algorithm ?? Ed25519();

  /// kid -> base64 raw 32-byte Ed25519 public key.
  final Map<String, String> publicKeys;
  final bool requireSignature;
  final SignatureAlgorithm _algorithm;

  static const String _envelopeKey = 'signature';
  static const String _expectedAlgorithm = 'ed25519';
  static const int _supportedEnvelopeVersion = 1;

  /// Examines [rawDocument] — the exact bytes the API served, or the exact
  /// bytes replayed out of the offline store.
  ///
  /// [hasSeenSignedManifest] is the per-device ratchet. It is passed in rather
  /// than read here so this class stays a pure function of its inputs and the
  /// policy table can be asserted directly.
  Future<ManifestVerification> verify(
    String rawDocument, {
    required bool hasSeenSignedManifest,
  }) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(rawDocument) as Map<String, dynamic>;
    } catch (_) {
      return const ManifestVerification.rejected(ManifestRejection.malformed);
    }

    final envelope = body[_envelopeKey];
    if (envelope == null) {
      return _unverified(body, ManifestRejection.signatureMissing, hasSeenSignedManifest);
    }
    if (envelope is! Map<String, dynamic>) {
      return _unverified(body, ManifestRejection.signatureUnknownKey, hasSeenSignedManifest);
    }

    final kid = envelope['kid'];
    final publicKeyB64 = kid is String ? publicKeys[kid] : null;
    final usable = publicKeyB64 != null &&
        envelope['alg'] == _expectedAlgorithm &&
        envelope['sv'] == _supportedEnvelopeVersion &&
        envelope['payload'] is String &&
        envelope['sig'] is String;

    // Not judgeable: an unknown key, an algorithm or envelope version from a
    // future server, or a shape we do not recognise. Deliberately NOT treated
    // as tampering — see the class comment.
    if (!usable) {
      return _unverified(body, ManifestRejection.signatureUnknownKey, hasSeenSignedManifest);
    }

    final payload = envelope['payload'] as String;
    final ok = await _signatureHolds(
      publicKeyB64: publicKeyB64,
      signingInput: '${envelope['sv']}.$kid.$payload',
      signature: envelope['sig'] as String,
    );
    if (!ok) {
      // Past this point the key is one we hold, so a failure is a statement
      // about the document, not about our configuration.
      return const ManifestVerification.rejected(ManifestRejection.signatureInvalid);
    }

    final signed = _decodeSignedDocument(payload);
    if (signed == null) {
      return const ManifestVerification.rejected(ManifestRejection.signatureInvalid);
    }

    return ManifestVerification.accepted(
      OfflineManifest.fromJson(signed, trust: ManifestTrust.signed),
      ManifestTrust.signed,
      signingKeyId: kid as String,
    );
  }

  /// The unverified branch: accept the plain body, or refuse it, depending on
  /// the ratchet and the compile-time policy.
  ManifestVerification _unverified(
    Map<String, dynamic> body,
    ManifestRejection reason,
    bool hasSeenSignedManifest,
  ) {
    if (requireSignature || hasSeenSignedManifest) {
      return ManifestVerification.rejected(reason);
    }
    try {
      return ManifestVerification.accepted(
        OfflineManifest.fromJson(body, trust: ManifestTrust.unsigned),
        ManifestTrust.unsigned,
      );
    } catch (_) {
      return const ManifestVerification.rejected(ManifestRejection.malformed);
    }
  }

  Future<bool> _signatureHolds({
    required String publicKeyB64,
    required String signingInput,
    required String signature,
  }) async {
    try {
      final key = SimplePublicKey(base64.decode(publicKeyB64), type: KeyPairType.ed25519);
      return await _algorithm.verify(
        utf8.encode(signingInput),
        signature: Signature(_decodeBase64Url(signature), publicKey: key),
      );
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic>? _decodeSignedDocument(String payload) {
    try {
      return jsonDecode(utf8.decode(_decodeBase64Url(payload))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The API emits base64url without padding (RFC 4648 §5); `base64Url.decode`
  /// requires it. Restore it rather than asking the server to pad, so the wire
  /// format stays the same shape as the existing ticket token encoding.
  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(value.padRight((value.length + 3) & ~3, '='));
}
