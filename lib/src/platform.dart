import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// The native store behind [CloudPreferences].
///
/// Swapped for [InMemoryCloudPreferencesStore] in tests.
abstract class CloudPreferencesStore {
  /// Opens the store and returns all locally stored values.
  Future<Map<String, Object>> initialize({required bool liveSync});

  /// Stores [value] under [key].
  Future<void> setValue(String key, Object value);

  /// Removes [key].
  Future<void> remove(String key);

  /// Removes every key.
  Future<void> clear();

  /// Values that changed outside the app.
  Stream<StoreChange> get changes;
}

/// The store that talks to the native plugin through Pigeon.
class PigeonCloudPreferencesStore implements CloudPreferencesStore {
  final CloudPreferencesHostApi _api = CloudPreferencesHostApi();

  @override
  Future<Map<String, Object>> initialize({required bool liveSync}) =>
      _api.initialize(liveSync);

  @override
  Future<void> setValue(String key, Object value) => _api.setValue(key, value);

  @override
  Future<void> remove(String key) => _api.remove(key);

  @override
  Future<void> clear() => _api.clear();

  @override
  Stream<StoreChange> get changes => watchChanges();
}

/// An in-memory store for tests.
///
/// Use [CloudPreferences.setMockInitialValues] instead of creating this
/// directly. Call [emit] to simulate a restore or a live change.
@visibleForTesting
class InMemoryCloudPreferencesStore implements CloudPreferencesStore {
  /// Creates a store that starts with [values].
  InMemoryCloudPreferencesStore(Map<String, Object> values)
    : values = Map.of(values);

  /// The values currently stored.
  final Map<String, Object> values;

  /// The `liveSync` flag the store was opened with, or null before
  /// [initialize].
  bool? liveSync;

  final StreamController<StoreChange> _changes = StreamController.broadcast();

  @override
  Future<Map<String, Object>> initialize({required bool liveSync}) async {
    this.liveSync = liveSync;
    return Map.of(values);
  }

  @override
  Future<void> setValue(String key, Object value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Stream<StoreChange> get changes => _changes.stream;

  /// Applies [change] to [values] and delivers it to [CloudPreferences].
  void emit(StoreChange change) {
    for (final key in change.keys) {
      final value = change.values[key];
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    }
    _changes.add(change);
  }
}
