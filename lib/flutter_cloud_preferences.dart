/// Key-value preferences that survive reinstalls and new devices.
///
/// Values are stored locally and backed up to iCloud key-value storage on iOS
/// and macOS, and to Android Auto Backup on Android. See [CloudPreferences].
library;

export 'src/cloud_preferences.dart';
export 'src/events.dart';
export 'src/limits.dart'
    show CloudPreferencesLimitException, CloudPreferencesLimits;
