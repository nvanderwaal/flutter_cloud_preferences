import 'package:flutter/foundation.dart';

/// Why values changed outside the app while it was running.
///
/// Only reported when live sync is on; see [CloudPreferences.getInstance].
enum CloudPreferencesChangeReason {
  /// Another device on the same iCloud account changed values.
  serverChange,

  /// The first sync after the user signed into iCloud on this device.
  initialSync,

  /// The app exceeded the iCloud key-value storage quota and some values
  /// were rejected.
  quotaViolation,

  /// The user signed into a different iCloud account; values were replaced
  /// with those of the new account.
  accountChange,
}

/// Values restored from the cloud after [CloudPreferences.getInstance]
/// returned.
///
/// On a fresh install on iOS or macOS, iCloud delivers its data in the
/// background. Restored values only fill keys the app has not written yet.
/// On Android, Auto Backup restores data before the app first starts, so this
/// event is never emitted there.
@immutable
class CloudPreferencesRestoreEvent {
  /// Creates a restore event for [keys].
  const CloudPreferencesRestoreEvent(this.keys);

  /// The keys that received a restored value.
  final Set<String> keys;

  @override
  String toString() => 'CloudPreferencesRestoreEvent($keys)';
}

/// Values that another device changed, delivered in live sync mode.
@immutable
class CloudPreferencesChange {
  /// Creates a change event.
  const CloudPreferencesChange(this.reason, this.keys);

  /// Why the values changed.
  final CloudPreferencesChangeReason reason;

  /// The keys that changed, including removed keys.
  final Set<String> keys;

  @override
  String toString() => 'CloudPreferencesChange($reason, $keys)';
}
