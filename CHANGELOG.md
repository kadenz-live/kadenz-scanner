# Changelog

All notable changes to the Kadenz Scanner are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
