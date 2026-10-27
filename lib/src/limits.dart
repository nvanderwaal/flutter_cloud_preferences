import 'dart:convert';
import 'dart:typed_data';

/// Storage limits, taken from iCloud key-value storage and applied on every
/// platform so an app that works on Android also works on iOS.
abstract final class CloudPreferencesLimits {
  /// Maximum length of a key in UTF-8 bytes.
  static const int maxKeyBytes = 64;

  /// Maximum number of keys.
  static const int maxKeys = 1024;

  /// Maximum total size of all keys and values in bytes.
  static const int maxTotalBytes = 1024 * 1024;
}

/// Thrown when a write would exceed one of the [CloudPreferencesLimits].
///
/// Nothing is written when this is thrown.
class CloudPreferencesLimitException implements Exception {
  /// Creates an exception for a write to [key] that broke a limit.
  const CloudPreferencesLimitException(this.key, this.message);

  /// The key that was being written.
  final String key;

  /// What limit was exceeded.
  final String message;

  @override
  String toString() => 'CloudPreferencesLimitException($key): $message';
}

/// The number of bytes [key] and [value] count towards
/// [CloudPreferencesLimits.maxTotalBytes].
///
/// This mirrors how iCloud key-value storage counts usage: UTF-8 bytes for
/// keys and strings, raw length for bytes, and 8 bytes for numbers.
int storedSize(String key, Object value) => utf8Length(key) + _valueSize(value);

/// The length of [text] in UTF-8 bytes.
int utf8Length(String text) => utf8.encode(text).length;

int _valueSize(Object value) => switch (value) {
  String() => utf8Length(value),
  bool() => 1,
  int() || double() => 8,
  Uint8List() => value.length,
  List<String>() => value.fold(0, (sum, item) => sum + utf8Length(item)),
  _ => throw ArgumentError.value(value, 'value', 'Unsupported type'),
};
