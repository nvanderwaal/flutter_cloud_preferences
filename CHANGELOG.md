## 0.3.0

* Compatible with Flutter 3.50.
* Android: built with Android Gradle Plugin 9.3.1 and Kotlin 2.4.20.
* Platform bindings regenerated with Pigeon 30. No API changes.
* The example app uses the standalone `material_ui` package and requires
  Flutter 3.47 or later. The package's own SDK constraints are unchanged.
* README: a table of which package version is tested with which Flutter
  version.

## 0.2.0

* `CloudPreferences.configure()` sets the store's options once, before the
  first `getInstance()`.
* Local-only keys: `configure(localOnlyKeys: {...})` keeps values such as auth
  tokens and device IDs on the device. They are never mirrored to iCloud, never
  included in Auto Backup or device backups, and never restored.
* `getInstance(liveSync:)` is deprecated and will be removed in 1.0; use
  `configure(liveSync: true)`.
* iOS and macOS: a key the app removes before the background restore arrives
  is no longer brought back by it.
* iOS and macOS: values written before iCloud's first download are written to
  iCloud again once it arrives, instead of being lost there.
* iOS and macOS: a restore that has not arrived when the app is closed now
  continues on the next launch.

## 0.1.0

* First release.
* `CloudPreferences`: key-value preferences with cached synchronous reads for
  `String`, `bool`, `int`, `double`, `List<String>` and `Uint8List`.
* iOS and macOS: values stored in `UserDefaults` and mirrored to iCloud
  key-value storage; restored on a fresh install and reported on `onRestored`;
  opt-in live sync with `changes`.
* Android: values stored in a SharedPreferences file that Android Auto Backup
  restores on reinstall and new devices.
* iCloud key-value storage limits (64-byte keys, 1024 keys, 1 MB) enforced on
  every platform.
