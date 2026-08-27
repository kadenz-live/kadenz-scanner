# Changelog

All notable changes to the Kadenz Scanner are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

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
