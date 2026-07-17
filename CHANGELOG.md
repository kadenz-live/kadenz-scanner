# Changelog

All notable changes to the Kadenz Scanner are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

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
