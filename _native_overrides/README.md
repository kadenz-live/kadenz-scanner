# Native overrides

The `ios/` and `android/` folders are intentionally **generated** by the Flutter SDK
(via `flutter create`) — the generated files include binary blobs (Gradle wrapper JAR,
default app icons), Xcode project files (`.pbxproj`), and Gradle plugin versions that
must match the Flutter SDK on your machine. Hand-writing them would be brittle.

After you run `./setup.sh` (which calls `flutter create .`), the generator produces
two files that we need to override with project-specific values:

- **`ios/Runner/Info.plist`** — needs `NSCameraUsageDescription` so iOS allows the
  QR scanner to use the camera, and `NSAllowsLocalNetworking` so the app can talk
  to your dev API over HTTP.
- **`android/app/src/main/AndroidManifest.xml`** — needs `<uses-permission android:name="android.permission.CAMERA"/>`
  and `android:usesCleartextTraffic="true"` for HTTP dev API access.

`setup.sh` automatically copies the patched versions over the generated ones.

If Flutter is updated and these files diverge in incompatible ways, re-merge by hand:
keep the generator's file as the base and re-add the camera/network entries shown here.
