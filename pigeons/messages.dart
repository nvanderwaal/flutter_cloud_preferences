// Regenerate with: dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/flutter_cloud_preferences/Sources/flutter_cloud_preferences/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOut:
        'android/src/main/kotlin/io/github/nvanderwaal/flutter_cloud_preferences/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.nvanderwaal.flutter_cloud_preferences',
    ),
    dartPackageName: 'flutter_cloud_preferences',
  ),
)
/// Why the native store reported a change.
enum StoreChangeReason {
  /// Values from a previous install or another device were restored into
  /// keys the app had not written yet.
  restored,

  /// Live sync only: another device changed values.
  serverChange,

  /// Live sync only: the first sync after the user signed into iCloud.
  initialSync,

  /// Live sync only: the app exceeded the iCloud key-value storage quota.
  quotaViolation,

  /// Live sync only: the iCloud account changed.
  accountChange,
}

/// A batch of values that changed outside the app.
class StoreChange {
  StoreChange({required this.reason, required this.keys, required this.values});

  StoreChangeReason reason;

  /// Every key that changed, including removed ones.
  List<String> keys;

  /// The new values of the changed keys. A key in [keys] that is missing here
  /// was removed.
  Map<String, Object> values;
}

@HostApi()
abstract class CloudPreferencesHostApi {
  /// Opens the store and returns all locally stored values.
  ///
  /// With [liveSync] false, cloud values are only read back on a fresh
  /// install. With [liveSync] true (Apple platforms only), external changes
  /// are applied and reported as they arrive.
  Map<String, Object> initialize(bool liveSync);

  /// Stores [value] locally and mirrors it to the cloud.
  void setValue(String key, Object value);

  /// Removes [key] locally and from the cloud.
  void remove(String key);

  /// Removes every key locally and from the cloud.
  void clear();
}

@EventChannelApi()
abstract class CloudPreferencesEventApi {
  StoreChange watchChanges();
}
