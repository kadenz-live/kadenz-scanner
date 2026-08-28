# Changelog

All notable changes to the Kadenz Scanner are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The scanned QR token is now documented and test-locked as **opaque** to this
  app. The API signs tokens from a keyring and stamps the signing-key id into
  the payload so the signing secret can finally be rotated without invalidating
  tickets already in wallets (kadenz#1827 / ADR-0055). No behaviour change was
  needed here — online the token is forwarded verbatim, offline the whole
  string is SHA-256'd against the manifest digest, so a token carrying a key id
  already worked. That is now a contract with regression tests behind it rather
  than a happy accident: `test/token_opacity_test.dart` verifies both token
  shapes against server-computed digests, including an event holding tickets
  from both sides of a rotation. A future change that parses the token
  client-side would fail there instead of at a door.

### Security

- The offline manifest is now verified before any of it is trusted. It carries
  a detached Ed25519 signature covering the whole document — the admissible
  set, every entry status, and the `valid_until` the scanner has honoured over
  its own 12-hour constant since kadenz#1778. Until now all of that arrived
  unauthenticated and sat in `SharedPreferences` on a device door staff hold,
  so the fields the offline admit decision actually turns on were editable
  local state. The signature is over the exact bytes the server produced, so it
  cannot cover only part of the document; the app reads the manifest out of the
  signed payload and ignores the plain body. Private keys never leave the API.
  See kadenz#1823 / ADR-0055.

  Three deliberate choices in how it fails:

  - **A refused manifest never evicts the one already in hand.** A door holding
    a valid manifest is not bricked by a bad one arriving; it keeps admitting
    until that manifest legitimately expires, and the operator is told the sync
    was refused and why. Clearing on rejection would hand anyone who can put one
    bad response in front of the device the ability to shut the door.
  - **An unverifiable manifest is tolerated exactly once per device.** During
    rollout a scanner on this build may meet an API whose signing key is not
    provisioned yet; refusing there would take doors down for an ordering
    problem. The tolerance is closed by a one-way ratchet the first time the
    device verifies anything, and never reopens — without it, "tolerate
    unsigned" would be a permanent downgrade available to anyone who strips a
    field.
  - **A key we do not hold is not treated as tampering.** Key ids are
    fingerprints of the key itself, so a server signing with something this
    build has not pinned reads as "unknown key" (soft, ride out on the last
    known good) rather than "bad signature" (reject). A configuration mismatch
    cannot present as an attack.

  The stored manifest is re-verified on every load, not only at sync: local
  storage is not a trust boundary.

- Login no longer gates on the user's role string. The old check admitted only
  `'scanner'` or `'admin'`, which meant a `global_admin` could not sign in, the
  server never emits `'admin'` at all, and — the part that mattered — a door
  operator holding an `einlass` membership on the account whose events they
  work was turned away. The single role that passed was exactly the one the API
  short-circuited to platform-wide scan authority, so the client gate was what
  forced every door device onto platform-wide authority. The scanner now models
  no authority of its own: it asks the API whether this operator may reach the
  scanner surface and takes that answer, so a future change to the authority
  model needs no scanner release. See kadenz#1816 / ADR-0054.
  Only an explicit `403` is treated as a refusal — a server fault is not an
  authorization answer, and turning one into a login refusal would lock door
  staff out during an outage.

### Added

- `X-Device-Id` is now sent on sign-in and on every API call, not only on the
  manifest fetch. The API binds it to the session row at login, which makes
  "revoke this phone" an available operation instead of only "revoke this
  session" (which the device re-establishes at the next login). The header
  carries no authority — it is a revocation and forensic handle.

### Changed

- The camera-fault panel now offers only actions the operator can actually
  take. Retry is gone from the "no camera available" fault — no restart makes
  absent hardware appear — and the escape hatch is manual entry where an event
  is selected, or a step back to the event picker where it is not. The English
  retry label is now "Try again", matching the event picker's identical button
  (the German label was already „Erneut versuchen").

### Fixed

- Camera-fault hint no longer points at a control that is not on screen: in
  "Any event" mode manual entry is gated off (the `validate_code` endpoint is
  event-scoped), so the panel now says to go back and select an event instead
  of promising manual entry. Hint, panel button and app-bar control all hang
  off one predicate, and a fault x entry-mode matrix test pins that no
  combination leaves the door without a working action.

- Bumped `audioplayers` from `^5.2.1` to `^6.8.1` so `audioplayers_android`
  compiles against Android API 34+ (was API 33), fixing the release
  `appbundle` build failing at `checkReleaseAarMetadata` against its own
  `androidx` transitive dependencies.

## [1.17.6] - 2026-07-17

### Added

- Public open-source release of the Kadenz ticket-validation client, extracted
  from the Kadenz monorepo into its own repository.

### Changed

- Brand assets: the splash screen now shows the Solid ticket-mark lockup —
  `wordmark.png` is the white stacked mark + constructed `kadenz.` wordmark
  (outlined geometry, no font dependency), `splash_logo.png` is the white mark
  alone (circle-safe for the Android 12 splash mask), and the pre-brand
  `icon_source.svg` "K" tile is replaced by the flat ticket-mark tile.

[Unreleased]: https://github.com/kadenz-live/kadenz-scanner/compare/app-v1.17.6...HEAD
[1.17.6]: https://github.com/kadenz-live/kadenz-scanner/releases/tag/app-v1.17.6
