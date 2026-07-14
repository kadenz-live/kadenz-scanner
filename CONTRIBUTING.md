# Contributing to Kadenz Scanner

Thanks for your interest. This repository is the open-source ticket-validation
client for [Kadenz](https://kadenz.live). Contributions are welcome — please
keep them focused and discuss anything non-trivial in an issue first.

## Before you start

- **Open an issue first** for bugs and features, so we can agree on scope before
  you spend time. Small, obvious fixes (typos, a clearly-broken test) can go
  straight to a PR.
- For **security problems, do not open an issue** — see [SECURITY.md](SECURITY.md).

## Development setup

You need the Flutter SDK (`>=3.24.0`, Dart `>=3.5.0`). Then:

```bash
./setup.sh          # materialises ios/ + android/ and runs flutter pub get
flutter run         # against production; see README for local API overrides
```

## Before you open a PR

The CI runs exactly these — please make sure they pass locally:

```bash
flutter analyze --fatal-warnings --fatal-infos
flutter test --coverage
```

- **Analyzer is strict**: warnings and info hints fail CI. Keep the tree clean
  (no unused imports, no dead code).
- **Add or update tests** for behaviour you change. The `test/` directory mirrors
  `lib/`.
- **Localisation**: user-facing strings live in `lib/l10n/app_en.arb` and
  `lib/l10n/app_de.arb` — add both.

## Pull request conventions

- Keep PRs small and single-purpose.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for the PR
  title (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `ci:`).
- Reference the issue you are closing (`Closes #123`).
- Fill in the PR template's test-plan section.

## What lives where

| Path | What |
|---|---|
| `lib/screens/` | UI screens |
| `lib/services/` | API, auth, offline validation, attestation, storage |
| `lib/models/` | Data models (manifest, events, validation results) |
| `lib/l10n/` | Localised strings (`.arb`) |
| `_native_overrides/` | Patches overlaid onto the generated native projects |
| `test/` | Widget + unit tests |

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
