/// Ed25519 public keys this build will accept on an offline manifest
/// (kadenz#1823, ADR-0055).
///
/// Only public keys live here. The private halves never leave the API — that is
/// the whole point of using a signature rather than a MAC: the party holding
/// the device is in scope as an adversary, so any key the device could verify
/// with symmetrically would also be a key it could forge with.
///
/// ## Key ids are fingerprints, not counters
///
/// A `kid` is the first 8 hex characters of SHA-256 over the raw 32-byte public
/// key. That makes "a key I do not hold" and "the key I hold, with a bad
/// signature" impossible to confuse, which matters because those two need
/// opposite responses: the first is a soft failure the door rides out on its
/// last-known-good manifest, the second is a tamper signal. With counter ids a
/// mere key mismatch between server and app would present as tampering and
/// could take a door down over a configuration error.
///
/// ## Adding the production key
///
/// `bin/rails manifest_signing:generate_key` on the API prints both halves and
/// the line to paste into [_pinnedProductionKeys]. Either pin it here and ship
/// a release, or pass it to the release build without a code change:
///
///   flutter build apk --dart-define=KADENZ_MANIFEST_SIGNING_KEYS=`kid`:`base64`
///
/// The build-time define is additive — it does not replace what is pinned — so
/// a rotation can be rolled out either way.
library;

import 'package:flutter/foundation.dart';

/// Production/staging keys compiled into every build.
///
/// Empty until the API's `MANIFEST_SIGNING_KEY_V1` has been generated. That is
/// deliberately not a blocker: with nothing pinned, a signed manifest reads as
/// "signed by a key I do not know", which is tolerated until this device has
/// verified something (see `ManifestVerifier`). Doors keep working; nothing is
/// verified yet.
const Map<String, String> _pinnedProductionKeys = <String, String>{
  // '5859c087': '<base64 raw ed25519 public key>',
};

/// Development keypair, accepted **only in debug builds**.
///
/// Its private half is committed in the API repo
/// (`Scanning::ManifestSigner::DEV_SEED_B64`) so that local runs and CI
/// exercise the signed path rather than leaving it as a branch that only ever
/// executes in production. A release build refuses it, so a manifest signed
/// with it cannot admit anyone through a real door.
const Map<String, String> kDevelopmentManifestSigningKeys = <String, String>{
  '1e094ef6': '5l8ORBtOj9/hHwSNTd6CbD187hba9nnxbMI6KyVusjA=',
};

/// `kid:base64[,kid:base64...]`, supplied at build time.
const String _keysFromBuild = String.fromEnvironment('KADENZ_MANIFEST_SIGNING_KEYS');

/// The keyring this build verifies against.
///
/// [debug] is injectable so a test can assert what a *release* build would
/// accept without being compiled in release mode — the "release refuses the
/// development key" property is only worth having if it is actually asserted.
Map<String, String> manifestSigningPublicKeys({
  bool debug = kDebugMode,
  String fromBuild = _keysFromBuild,
}) {
  return <String, String>{
    ..._pinnedProductionKeys,
    if (debug) ...kDevelopmentManifestSigningKeys,
    ...parseManifestSigningKeys(fromBuild),
  };
}

/// Parses the `--dart-define` form. Malformed entries are skipped rather than
/// thrown on: a typo in a build flag should cost verification coverage, which
/// fails soft, not app startup at a door.
Map<String, String> parseManifestSigningKeys(String source) {
  final keys = <String, String>{};
  for (final entry in source.split(',')) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    final separator = trimmed.indexOf(':');
    if (separator <= 0 || separator == trimmed.length - 1) continue;
    keys[trimmed.substring(0, separator).trim()] = trimmed.substring(separator + 1).trim();
  }
  return keys;
}
