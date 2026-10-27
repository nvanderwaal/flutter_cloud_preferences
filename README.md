# flutter_cloud_preferences

[![pub package](https://img.shields.io/pub/v/flutter_cloud_preferences.svg)](https://pub.dev/packages/flutter_cloud_preferences)
[![CI](https://github.com/nvanderwaal/flutter_cloud_preferences/actions/workflows/ci.yml/badge.svg)](https://github.com/nvanderwaal/flutter_cloud_preferences/actions/workflows/ci.yml)

Key-value preferences that survive reinstalls and new devices.

Values are saved locally and backed up to the platform's cloud: **iCloud key-value storage** on iOS and macOS, **Android Auto Backup** on Android. When the app is reinstalled or set up on a new device, the values come back. The API works like [`shared_preferences`](https://pub.dev/packages/shared_preferences): load once, then read synchronously.

```dart
final prefs = await CloudPreferences.getInstance();
await prefs.setBool('darkMode', true);
final darkMode = prefs.getBool('darkMode') ?? false;
```

## How it works

| | iOS / macOS | Android |
| --- | --- | --- |
| Local store | `UserDefaults` | A `SharedPreferences` file |
| Backed up to | iCloud key-value storage, on every write | Android Auto Backup, about once a day |
| Restored | In the background on the first launch after an install | Before the app first starts after an install |
| Live sync between running devices | Opt-in (`liveSync: true`) | Not available |
| Minimum version | iOS 15, macOS 12 | Android 7 (API 24) |

The local store is always the source of truth. The cloud copy is only read back on a fresh install or a new device, and a restored value never overwrites one the app has already written.

Use it for small things a user would expect to keep: settings, onboarding flags, a selected theme. Do **not** store secrets or tokens (values are not encrypted on the device; use [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)), and do not use it as a database (see [Limits](#limits)).

## Installation

```sh
flutter pub add flutter_cloud_preferences
```

Then set up each platform below. Without the setup, the package still works, but values are only stored locally.

### iOS and macOS

iCloud key-value storage needs the iCloud capability, which needs a paid Apple Developer Program membership.

1. Open `ios/Runner.xcworkspace` (or `macos/Runner.xcworkspace`) in Xcode.
2. Select the **Runner** target, then **Signing & Capabilities**, and pick your team.
3. Click **+ Capability**, add **iCloud**, and tick **Key-value storage**.

Xcode adds this to the app's entitlements file:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

On macOS, check that the key is in both `DebugProfile.entitlements` and `Release.entitlements`. A macOS app with this entitlement but no matching provisioning profile is stopped at launch, so let Xcode manage signing.

To test the restore, sign into iCloud on a device or simulator, run the app, change some values, delete the app and run it again. The values can take a few seconds to arrive; see [Restored values](#restored-values).

### Android

Nothing to do in a default Flutter app: Auto Backup is on unless the app turns it off.

- If your `AndroidManifest.xml` sets `android:allowBackup="false"`, nothing is backed up.
- If your app has custom backup rules, include the plugin's file. For `android:fullBackupContent` (Android 11 and lower):

  ```xml
  <full-backup-content>
      <include domain="sharedpref" path="flutter_cloud_preferences.xml" />
  </full-backup-content>
  ```

  For `android:dataExtractionRules` (Android 12 and higher):

  ```xml
  <data-extraction-rules>
      <cloud-backup>
          <include domain="sharedpref" path="flutter_cloud_preferences.xml" />
      </cloud-backup>
      <device-transfer>
          <include domain="sharedpref" path="flutter_cloud_preferences.xml" />
      </device-transfer>
  </data-extraction-rules>
  ```

The user needs backup turned on in their device settings. Android runs the backup by itself, roughly once a day when the device is idle, charging and on Wi-Fi.

To test a restore without waiting, use a release build. A debug build keeps about 55 MB of Flutter assets in `app_flutter/flutter_assets`, which is over the 25 MB Auto Backup limit, so Android skips the whole backup (logcat shows `Transport quota exceeded`). To test with a debug build, exclude that folder in your backup rules, as the [example app](example/android/app/src/main/res/xml) does.

```sh
flutter run --release       # change some values in the app
adb shell bmgr enable true
adb shell bmgr backupnow @pm@ <your.package.name>
adb uninstall <your.package.name>
flutter run --release       # values are restored on install
```

`backupnow` needs `@pm@` so the package list in the backup includes your app; without it the restore skips the app.

## Usage

### Reading and writing

```dart
final prefs = await CloudPreferences.getInstance();

await prefs.setString('name', 'Ada');
await prefs.setBool('darkMode', true);
await prefs.setInt('launchCount', 3);
await prefs.setDouble('volume', 0.8);
await prefs.setStringList('favorites', ['tea', 'cake']);
await prefs.setBytes('avatarHash', Uint8List.fromList([1, 2, 3]));

prefs.getString('name');        // 'Ada'
prefs.getStringList('missing'); // null
prefs.containsKey('darkMode');  // true
prefs.getKeys();                // {'name', 'darkMode', ...}

await prefs.remove('name');
await prefs.clear();
```

Reads come from an in-memory copy, so they are synchronous. Writes update that copy at once and complete when the native store has saved the value. A typed getter throws a `TypeError` if the stored value has another type.

### Restored values

On Android, restored values are already there when the app starts. On iOS and macOS, iCloud can deliver them a few seconds after launch. `getInstance()` does not wait for them; instead, listen to `onRestored` and refresh your UI:

```dart
prefs.onRestored.listen((event) {
  // event.keys holds the keys that received a restored value.
  setState(() {});
});
```

### Live sync (iOS and macOS only)

By default, values that another device changes are not applied while your app runs. To keep all devices on the same Apple ID in sync, turn on live sync and listen to `changes`:

```dart
final prefs = await CloudPreferences.getInstance(liveSync: true);

prefs.changes.listen((change) {
  // change.reason: serverChange, initialSync, quotaViolation or accountChange
  // change.keys: the keys that changed, including removed ones
  setState(() {});
});
```

Every `getInstance()` call in the app must use the same `liveSync` value. On Android the flag is ignored, because Android has no live sync.

## Limits

These are the limits of iCloud key-value storage. The package applies them on every platform, so an app that works on Android also works on iOS.

| Limit | Value |
| --- | --- |
| Key length | 64 bytes (UTF-8) |
| Number of keys | 1024 |
| Total size of keys and values | 1 MB |

A write that breaks a limit throws a `CloudPreferencesLimitException` and stores nothing. Supported value types are `String`, `bool`, `int`, `double`, `List<String>` and `Uint8List`. To store a map, `jsonEncode` it into a string.

## Testing

Replace the native store with an in-memory one before calling `getInstance()`:

```dart
setUp(() {
  CloudPreferences.setMockInitialValues({'darkMode': true});
});
```

## Migrating from shared_preferences

Copy the values you want backed up once, then read them from `CloudPreferences`:

```dart
final old = SharedPreferencesAsync();
final prefs = await CloudPreferences.getInstance();

if (!prefs.containsKey('migrated')) {
  final theme = await old.getString('theme');
  if (theme != null) await prefs.setString('theme', theme);
  await prefs.setBool('migrated', true);
}
```

## Troubleshooting

**Values don't come back on iOS.** Check that the iCloud capability with Key-value storage is enabled, that the device is signed into iCloud, and listen to `onRestored`, since values can arrive after launch.

**Values don't come back on Android.** Check that backup is on in the device settings and that `allowBackup` is not `false`. If the app has custom backup rules, include `flutter_cloud_preferences.xml`. Use the `bmgr` commands above to force a backup. If logcat shows `Transport quota exceeded`, the app's data is over 25 MB; debug builds always are, see above.

**The macOS app quits at launch.** The app has the iCloud entitlement without a matching provisioning profile. Let Xcode manage signing with your team.

**`liveSync` has no effect on Android.** That's expected: Android only restores on install.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/nvanderwaal/flutter_cloud_preferences). The native bindings are generated with Pigeon; after changing `pigeons/messages.dart`, run:

```sh
dart run pigeon --input pigeons/messages.dart
```

### Releasing

Releases are published to pub.dev from GitHub Actions. Bump `version` in `pubspec.yaml`, add the matching entry to `CHANGELOG.md`, merge to `main`, then push a tag for that version:

```sh
git tag v0.1.1
git push origin v0.1.1
```

## License

MIT, see [LICENSE](LICENSE).
