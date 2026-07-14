#!/usr/bin/env bash
# Generates the platform-specific iOS/Android scaffolding via the Flutter SDK,
# then overlays our project-specific patches (camera permission, app id, etc.).
#
# Run once after cloning:   ./setup.sh
# Re-running is safe and only re-applies the patches.

set -euo pipefail

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not on PATH. Install it from https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

ORG_ID="${ORG_ID:-com.example}"

# 1. Generate native projects (idempotent — won't overwrite lib/ or pubspec.yaml).
flutter create \
  --project-name kadenz_scanner \
  --org "$ORG_ID" \
  --platforms ios,android \
  --no-overwrite \
  .

# 2. Pull dependencies.
flutter pub get

# 3. Apply post-create patches (camera permissions + Android Manifest tweaks).
PATCH_DIR="_native_overrides"

if [ -f "$PATCH_DIR/ios/Info.plist.patch.plist" ]; then
  cp "$PATCH_DIR/ios/Info.plist.patch.plist" ios/Runner/Info.plist
  echo "✓ Replaced ios/Runner/Info.plist with camera-enabled version"
fi

if [ -f "$PATCH_DIR/android/AndroidManifest.xml" ]; then
  cp "$PATCH_DIR/android/AndroidManifest.xml" android/app/src/main/AndroidManifest.xml
  echo "✓ Replaced android/app/src/main/AndroidManifest.xml with camera-enabled version"
fi

# Overlay TestFlight/App Store release tooling (fastlane + export options).
# The .p8 App Store Connect API key is NEVER stored here — the Appfile/Fastfile
# reference it via the ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_FILEPATH env vars.
if [ -d "$PATCH_DIR/ios/fastlane" ]; then
  mkdir -p ios/fastlane
  cp "$PATCH_DIR/ios/fastlane/"* ios/fastlane/
  echo "✓ Installed ios/fastlane (Appfile, Fastfile, Pluginfile)"
fi

if [ -f "$PATCH_DIR/ios/ExportOptions.plist" ]; then
  cp "$PATCH_DIR/ios/ExportOptions.plist" ios/ExportOptions.plist
  echo "✓ Installed ios/ExportOptions.plist (app-store export config)"
fi

# 4. Regenerate branded app icon (iOS AppIcon + Android adaptive) and native
#    splash (iOS LaunchImage + Android 12+ window splash) from the sources in
#    assets/brand/. Idempotent — overwrites generator output only.
if [ -f assets/brand/icon_1024.png ]; then
  dart run flutter_launcher_icons >/dev/null
  echo "✓ Regenerated app icons from assets/brand/icon_1024.png"
fi

if [ -f assets/brand/splash_logo.png ]; then
  dart run flutter_native_splash:create >/dev/null
  echo "✓ Regenerated native splash from assets/brand/splash_logo.png"
fi

cat <<EOM

Done. Next steps:
  flutter run                       # runs on the first connected device/simulator
  flutter run -d "iPhone 15 Pro"
  flutter run -d emulator-5554

If you change ORG_ID or app name later, delete ios/ and android/, then re-run this script.
EOM
