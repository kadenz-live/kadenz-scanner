# Security policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Channel: **GitHub Private vulnerability reporting** — open the `Security` tab of
this repository and submit a report there. The advisory draft is visible only to
the maintainers and the reporter, and a fix can be coordinated from the same
place.

If GitHub PVR is unavailable to you, open a minimal public issue asking a
maintainer to reach out — **do not include vulnerability details in it.**

We aim to:

- Acknowledge receipt within **2 business days**.
- Provide a triage assessment within **5 business days**.
- Ship a fix or mitigation for confirmed High/Critical issues within **30 days**.

## Scope

In scope:

- The Flutter scanner app in this repository (`lib/`, `_native_overrides/`,
  `setup.sh`, the CI workflows).

Out of scope:

- The Kadenz backend that issues and signs tickets — it is a separate service.
  Report backend issues through the same private channel; they will be routed.
- Third-party services and packages we depend on (Apple, Google, pub.dev
  packages) — please report those to the respective vendor upstream.
- Local-development-only configuration that requires the attacker to already
  have the developer's machine.

## How the scanner protects tickets

The design goal is that **the client can recognise valid tickets but cannot
forge or mint them**, online or offline.

- **No signing secret on the device.** Offline validation is digest-matching:
  the server publishes SHA-256 digests of the tokens it has already HMAC-signed;
  the scanner hashes a scanned token and looks it up. The HMAC secret stays
  server-side. A stolen or reverse-engineered device leaks no signing key.
- **Auth tokens live in the platform keychain** via `flutter_secure_storage`,
  not in shared preferences or plaintext.
- **HTTPS is enforced for production hosts.** Plain `http://` is only permitted
  to localhost / `*.local` / RFC1918 for local development (ATS exception in
  `_native_overrides/ios/Info.plist.patch.plist`); it does not widen for public
  hosts. The login screen warns loudly on a non-HTTPS or unhealthy endpoint.
- **Device attestation (App Attest).** A scanner client attests to the backend
  before it is trusted (`lib/services/attestation_service.dart`).
- **Hardened release builds.** CI builds ship with `--obfuscate` and
  `--split-debug-info`, so a reversed binary reveals opaque symbols rather than
  method names.

## Supported versions

Security fixes target the latest released version. Given the app's small
surface, older builds are not separately backported — update to the latest
release.
