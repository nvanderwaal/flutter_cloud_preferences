import 'dart:async';

import 'package:flutter/foundation.dart';

import 'events.dart';
import 'limits.dart';
import 'messages.g.dart';
import 'platform.dart';

/// Key-value preferences that survive reinstalls and new devices.
///
/// Values are kept in a local store, which is the source of truth, and every
/// write is mirrored to the cloud: iCloud key-value storage on iOS and macOS,
/// Android Auto Backup on Android. The cloud copy is only read back on a fresh
/// install or a new device. Keys declared local-only with [configure] stay on
/// the device.
///
/// Reads are synchronous and come from an in-memory cache that is loaded by
/// [getInstance]. Writes update the cache immediately and complete once the
/// native store has saved the value.
///
/// ```dart
/// final prefs = await CloudPreferences.getInstance();
/// await prefs.setString('theme', 'dark');
/// final theme = prefs.getString('theme');
/// ```
class CloudPreferences {
  CloudPreferences._(
    this._store,
    this._cache,
    this.liveSync,
    this.localOnlyKeys,
  );

  static CloudPreferencesStore _storeOverride = PigeonCloudPreferencesStore();
  static Future<CloudPreferences>? _instance;
  static bool _configured = false;
  static bool _liveSync = false;
  static Set<String> _localOnlyKeys = const {};

  final CloudPreferencesStore _store;
  final Map<String, Object> _cache;
  final StreamController<CloudPreferencesRestoreEvent> _restored =
      StreamController.broadcast();
  final StreamController<CloudPreferencesChange> _changes =
      StreamController.broadcast();

  /// Whether live sync is on. See [configure].
  final bool liveSync;

  /// The keys that are never backed up or synced. See [configure].
  final Set<String> localOnlyKeys;

  /// Sets up the store. Call it once, before the first [getInstance], usually
  /// in `main()`. Without it, the defaults below apply.
  ///
  /// With [liveSync] set to true, iOS and macOS also apply values that other
  /// devices on the same iCloud account change while the app runs, and report
  /// them on [changes]. Android has no live sync, so the flag has no effect
  /// there. Defaults to false.
  ///
  /// Values of [localOnlyKeys] stay on this device: they are not mirrored to
  /// iCloud, not included in Auto Backup or device backups, and never
  /// restored. Use them for auth tokens, device IDs and other values that are
  /// wrong on another device. If a key is added to or removed from the set in
  /// a later version of the app, its stored value is moved on the next start.
  ///
  /// ```dart
  /// void main() {
  ///   CloudPreferences.configure(localOnlyKeys: {'authToken', 'deviceId'});
  ///   runApp(const MyApp());
  /// }
  /// ```
  ///
  /// Throws a [StateError] when called with other values after [getInstance]
  /// opened the store.
  static void configure({
    bool liveSync = false,
    Set<String> localOnlyKeys = const {},
  }) {
    if (_instance != null) {
      if (liveSync == _liveSync && setEquals(localOnlyKeys, _localOnlyKeys)) {
        return;
      }
      throw StateError(
        'CloudPreferences.configure() must be called before the first '
        'getInstance().',
      );
    }
    _configured = true;
    _liveSync = liveSync;
    _localOnlyKeys = Set.unmodifiable(localOnlyKeys);
  }

  /// Returns the shared instance, loading the local store on the first call.
  ///
  /// By default values are only read back from the cloud on a fresh install or
  /// a new device. On iOS and macOS that restore happens in the background
  /// after this returns; listen to [onRestored] to refresh the UI.
  ///
  /// The store uses the options given to [configure]. [liveSync] is kept for
  /// apps written for 0.1.0; a value that differs from the store's throws a
  /// [StateError].
  static Future<CloudPreferences> getInstance({
    @Deprecated('Use CloudPreferences.configure(liveSync: true) instead.')
    bool? liveSync,
  }) {
    if (liveSync != null && liveSync != _liveSync) {
      if (_instance != null || _configured) {
        throw StateError(
          'CloudPreferences was already set up with liveSync: $_liveSync.',
        );
      }
      _liveSync = liveSync;
    }
    return _instance ??= _open(_liveSync, _localOnlyKeys).catchError((
      Object error,
    ) {
      _instance = null;
      throw error;
    });
  }

  static Future<CloudPreferences> _open(
    bool liveSync,
    Set<String> localOnlyKeys,
  ) async {
    if (liveSync &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      debugPrint(
        'CloudPreferences: liveSync is not supported on Android and is ignored.',
      );
    }
    final store = _storeOverride;
    // Listen before initializing so no change is lost; apply them once the
    // cache is loaded.
    final pending = <StoreChange>[];
    CloudPreferences? prefs;
    store.changes.listen(
      (change) => prefs == null ? pending.add(change) : prefs._apply(change),
      onError: (Object error, StackTrace stackTrace) =>
          prefs?._changes.addError(error, stackTrace),
    );
    final values = await store.initialize(
      liveSync: liveSync,
      localOnlyKeys: localOnlyKeys,
    );
    prefs = CloudPreferences._(
      store,
      _normalize(values),
      liveSync,
      localOnlyKeys,
    );
    pending.forEach(prefs._apply);
    return prefs;
  }

  /// Replaces the native store with an in-memory one holding [values], and
  /// resets the shared instance and the options given to [configure].
  ///
  /// Call this in tests before [getInstance].
  @visibleForTesting
  static void setMockInitialValues(Map<String, Object> values) {
    setMockStore(InMemoryCloudPreferencesStore(values));
  }

  /// Replaces the native store with [store] and resets the shared instance
  /// and the options given to [configure].
  ///
  /// Use this in tests that need to simulate a restore or a live change
  /// through [InMemoryCloudPreferencesStore.emit].
  @visibleForTesting
  static void setMockStore(CloudPreferencesStore store) {
    _storeOverride = store;
    _instance = null;
    _configured = false;
    _liveSync = false;
    _localOnlyKeys = const {};
  }

  /// Values restored from the cloud after [getInstance] returned.
  ///
  /// Only emitted on iOS and macOS, on a fresh install or a new device.
  Stream<CloudPreferencesRestoreEvent> get onRestored => _restored.stream;

  /// Values that other devices changed. Only emitted when [liveSync] is on.
  Stream<CloudPreferencesChange> get changes => _changes.stream;

  /// All keys currently stored.
  Set<String> getKeys() => Set.of(_cache.keys);

  /// Whether a value is stored under [key].
  bool containsKey(String key) => _cache.containsKey(key);

  /// The value stored under [key], or null.
  Object? get(String key) => _cache[key];

  /// A copy of every stored value.
  Map<String, Object> getAll() => Map.of(_cache);

  /// The string stored under [key], or null.
  ///
  /// Throws a [TypeError] if the value is not a string; the same goes for the
  /// other typed getters.
  String? getString(String key) => _cache[key] as String?;

  /// The bool stored under [key], or null.
  bool? getBool(String key) => _cache[key] as bool?;

  /// The int stored under [key], or null.
  int? getInt(String key) => _cache[key] as int?;

  /// The double stored under [key], or null.
  double? getDouble(String key) => _cache[key] as double?;

  /// The string list stored under [key], or null.
  List<String>? getStringList(String key) {
    final value = _cache[key] as List<String>?;
    return value == null ? null : List.of(value);
  }

  /// The bytes stored under [key], or null.
  Uint8List? getBytes(String key) {
    final value = _cache[key] as Uint8List?;
    return value == null ? null : Uint8List.fromList(value);
  }

  /// Stores a string under [key].
  Future<void> setString(String key, String value) => _set(key, value);

  /// Stores a bool under [key].
  Future<void> setBool(String key, bool value) => _set(key, value);

  /// Stores an int under [key].
  Future<void> setInt(String key, int value) => _set(key, value);

  /// Stores a double under [key].
  Future<void> setDouble(String key, double value) => _set(key, value);

  /// Stores a list of strings under [key].
  Future<void> setStringList(String key, List<String> value) =>
      _set(key, List<String>.unmodifiable(value));

  /// Stores bytes under [key].
  Future<void> setBytes(String key, Uint8List value) =>
      _set(key, Uint8List.fromList(value));

  /// Removes [key].
  Future<void> remove(String key) {
    _cache.remove(key);
    return _store.remove(key);
  }

  /// Removes every key, locally and from the cloud.
  Future<void> clear() {
    _cache.clear();
    return _store.clear();
  }

  Future<void> _set(String key, Object value) {
    _checkLimits(key, value);
    _cache[key] = value;
    return _store.setValue(key, value);
  }

  void _checkLimits(String key, Object value) {
    // Local-only values never reach iCloud, so its limits don't apply.
    if (localOnlyKeys.contains(key)) return;
    if (utf8Length(key) > CloudPreferencesLimits.maxKeyBytes) {
      throw CloudPreferencesLimitException(
        key,
        'Keys can be at most ${CloudPreferencesLimits.maxKeyBytes} bytes in UTF-8.',
      );
    }
    final existing = _cache[key];
    final synced = _cache.keys.where((k) => !localOnlyKeys.contains(k));
    if (existing == null && synced.length >= CloudPreferencesLimits.maxKeys) {
      throw CloudPreferencesLimitException(
        key,
        'At most ${CloudPreferencesLimits.maxKeys} keys can be stored.',
      );
    }
    var total = 0;
    for (final k in synced) {
      total += storedSize(k, _cache[k]!);
    }
    if (existing != null) total -= storedSize(key, existing);
    if (total + storedSize(key, value) > CloudPreferencesLimits.maxTotalBytes) {
      throw CloudPreferencesLimitException(
        key,
        'All values together can be at most ${CloudPreferencesLimits.maxTotalBytes} bytes.',
      );
    }
  }

  void _apply(StoreChange change) {
    final values = _normalize(change.values);
    final keys = change.keys.where((key) => !localOnlyKeys.contains(key));
    if (change.reason == StoreChangeReason.restored) {
      // A restore never overwrites a value the app has written.
      final restored = <String>{};
      for (final key in keys) {
        final value = values[key];
        if (value != null && !_cache.containsKey(key)) {
          _cache[key] = value;
          restored.add(key);
        }
      }
      if (restored.isNotEmpty) {
        _restored.add(CloudPreferencesRestoreEvent(restored));
      }
      return;
    }
    if (keys.isEmpty) return;
    for (final key in keys) {
      final value = values[key];
      if (value == null) {
        _cache.remove(key);
      } else {
        _cache[key] = value;
      }
    }
    _changes.add(
      CloudPreferencesChange(_reasons[change.reason]!, Set.of(keys)),
    );
  }

  static const Map<StoreChangeReason, CloudPreferencesChangeReason> _reasons = {
    StoreChangeReason.serverChange: CloudPreferencesChangeReason.serverChange,
    StoreChangeReason.initialSync: CloudPreferencesChangeReason.initialSync,
    StoreChangeReason.quotaViolation:
        CloudPreferencesChangeReason.quotaViolation,
    StoreChangeReason.accountChange: CloudPreferencesChangeReason.accountChange,
  };

  /// Converts values decoded from the platform channel to the types the
  /// getters return. Values of unsupported types are dropped.
  static Map<String, Object> _normalize(Map<String, Object> values) {
    final result = <String, Object>{};
    values.forEach((key, value) {
      final normalized = switch (value) {
        String() || bool() || int() || double() || Uint8List() => value,
        List() when value.every((item) => item is String) =>
          List<String>.unmodifiable(value.cast<String>()),
        _ => null,
      };
      if (normalized != null) result[key] = normalized;
    });
    return result;
  }
}
