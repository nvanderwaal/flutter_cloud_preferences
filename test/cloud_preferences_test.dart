import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_cloud_preferences/flutter_cloud_preferences.dart';
import 'package:flutter_cloud_preferences/src/messages.g.dart';
import 'package:flutter_cloud_preferences/src/platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryCloudPreferencesStore store;

  setUp(() {
    store = InMemoryCloudPreferencesStore({});
    CloudPreferences.setMockStore(store);
  });

  group('reading and writing', () {
    test('loads initial values', () async {
      CloudPreferences.setMockInitialValues({'theme': 'dark', 'count': 3});
      final prefs = await CloudPreferences.getInstance();

      expect(prefs.getString('theme'), 'dark');
      expect(prefs.getInt('count'), 3);
      expect(prefs.getKeys(), {'theme', 'count'});
      expect(prefs.containsKey('missing'), isFalse);
      expect(prefs.get('missing'), isNull);
    });

    test('round-trips every supported type', () async {
      final prefs = await CloudPreferences.getInstance();
      final bytes = Uint8List.fromList([1, 2, 3]);

      await prefs.setString('string', 'value');
      await prefs.setBool('bool', true);
      await prefs.setInt('int', 1 << 40);
      await prefs.setDouble('double', 1.5);
      await prefs.setStringList('list', ['b', 'a', 'b']);
      await prefs.setBytes('bytes', bytes);

      expect(prefs.getString('string'), 'value');
      expect(prefs.getBool('bool'), isTrue);
      expect(prefs.getInt('int'), 1 << 40);
      expect(prefs.getDouble('double'), 1.5);
      expect(prefs.getStringList('list'), ['b', 'a', 'b']);
      expect(prefs.getBytes('bytes'), bytes);
      expect(store.values, hasLength(6));
    });

    test('updates the cache before the write completes', () async {
      final prefs = await CloudPreferences.getInstance();
      final write = prefs.setString('theme', 'dark');

      expect(prefs.getString('theme'), 'dark');
      await write;
    });

    test('returned lists and bytes cannot change the stored value', () async {
      final prefs = await CloudPreferences.getInstance();
      final list = ['a'];
      final bytes = Uint8List.fromList([1]);
      await prefs.setStringList('list', list);
      await prefs.setBytes('bytes', bytes);

      list.add('b');
      bytes[0] = 9;
      prefs.getStringList('list')!.add('c');
      prefs.getBytes('bytes')![0] = 8;

      expect(prefs.getStringList('list'), ['a']);
      expect(prefs.getBytes('bytes'), [1]);
    });

    test('typed getters throw on the wrong type', () async {
      CloudPreferences.setMockInitialValues({'count': 3});
      final prefs = await CloudPreferences.getInstance();

      expect(() => prefs.getString('count'), throwsA(isA<TypeError>()));
    });

    test('remove and clear', () async {
      CloudPreferences.setMockInitialValues({'a': 'x', 'b': 'y'});
      final prefs = await CloudPreferences.getInstance();

      await prefs.remove('a');
      expect(prefs.getKeys(), {'b'});

      await prefs.clear();
      expect(prefs.getKeys(), isEmpty);
    });

    test('normalizes values decoded from the platform channel', () async {
      CloudPreferences.setMockInitialValues({
        'list': <Object?>['a', 'b'],
        'unsupported': <Object?>[1, 2],
      });
      final prefs = await CloudPreferences.getInstance();

      expect(prefs.getStringList('list'), ['a', 'b']);
      expect(prefs.containsKey('unsupported'), isFalse);
    });
  });

  group('getInstance', () {
    test('returns the same instance', () async {
      expect(
        await CloudPreferences.getInstance(),
        same(await CloudPreferences.getInstance()),
      );
    });

    test('passes liveSync to the store, off by default', () async {
      final prefs = await CloudPreferences.getInstance();

      expect(prefs.liveSync, isFalse);
      expect(store.liveSync, isFalse);
    });

    test('opens the store with liveSync when asked', () async {
      final prefs = await CloudPreferences.getInstance(liveSync: true);

      expect(prefs.liveSync, isTrue);
      expect(store.liveSync, isTrue);
    });

    test('throws when liveSync differs from the first call', () async {
      await CloudPreferences.getInstance();

      expect(
        () => CloudPreferences.getInstance(liveSync: true),
        throwsStateError,
      );
    });

    test('later calls can leave out the options', () async {
      final prefs = await CloudPreferences.getInstance(
        liveSync: true,
        localOnlyKeys: {'token'},
      );

      expect(await CloudPreferences.getInstance(), same(prefs));
      expect(prefs.liveSync, isTrue);
      expect(prefs.localOnlyKeys, {'token'});
    });
  });

  group('local-only keys', () {
    test('are passed to the store, empty by default', () async {
      final prefs = await CloudPreferences.getInstance();

      expect(prefs.localOnlyKeys, isEmpty);
      expect(store.localOnlyKeys, isEmpty);
    });

    test('are passed to the store when given', () async {
      await CloudPreferences.getInstance(localOnlyKeys: {'token', 'deviceId'});

      expect(store.localOnlyKeys, {'token', 'deviceId'});
    });

    test('throw when they differ from the first call', () async {
      await CloudPreferences.getInstance(localOnlyKeys: {'token'});

      expect(
        () => CloudPreferences.getInstance(localOnlyKeys: {'deviceId'}),
        throwsStateError,
      );
      expect(
        await CloudPreferences.getInstance(localOnlyKeys: {'token'}),
        isNotNull,
      );
    });

    test('are read and written like other keys', () async {
      final prefs = await CloudPreferences.getInstance(
        localOnlyKeys: {'token'},
      );

      await prefs.setString('token', 'secret');
      expect(prefs.getString('token'), 'secret');
      expect(store.values['token'], 'secret');
    });

    test('are not restored or changed by live sync', () async {
      final prefs = await CloudPreferences.getInstance(
        liveSync: true,
        localOnlyKeys: {'token'},
      );
      final restored = <CloudPreferencesRestoreEvent>[];
      final changes = <CloudPreferencesChange>[];
      prefs.onRestored.listen(restored.add);
      prefs.changes.listen(changes.add);

      store.emit(
        StoreChange(
          reason: StoreChangeReason.restored,
          keys: ['token'],
          values: {'token': 'other device'},
        ),
      );
      store.emit(
        StoreChange(
          reason: StoreChangeReason.serverChange,
          keys: ['token'],
          values: {'token': 'other device'},
        ),
      );
      await pumpEventQueue();

      expect(prefs.containsKey('token'), isFalse);
      expect(restored, isEmpty);
      expect(changes, isEmpty);
    });

    test('do not count towards the iCloud limits', () async {
      CloudPreferences.setMockInitialValues({
        for (var i = 0; i < CloudPreferencesLimits.maxKeys; i++) 'key$i': i,
      });
      final prefs = await CloudPreferences.getInstance(
        localOnlyKeys: {'token'},
      );

      await prefs.setBytes(
        'token',
        Uint8List(CloudPreferencesLimits.maxTotalBytes),
      );
      expect(prefs.getBytes('token'), hasLength(1 << 20));
    });
  });

  group('limits', () {
    test('rejects keys over 64 UTF-8 bytes', () async {
      final prefs = await CloudPreferences.getInstance();

      await prefs.setString('k' * 64, 'ok');
      expect(
        () => prefs.setString('é' * 33, 'too long'),
        throwsA(isA<CloudPreferencesLimitException>()),
      );
    });

    test('rejects more than 1024 keys', () async {
      CloudPreferences.setMockInitialValues({
        for (var i = 0; i < CloudPreferencesLimits.maxKeys; i++) 'key$i': i,
      });
      final prefs = await CloudPreferences.getInstance();

      await prefs.setInt('key0', -1);
      expect(
        () => prefs.setInt('one-more', 1),
        throwsA(isA<CloudPreferencesLimitException>()),
      );
      expect(prefs.containsKey('one-more'), isFalse);
    });

    test('rejects writes over 1 MB in total', () async {
      final prefs = await CloudPreferences.getInstance();
      final half = Uint8List(CloudPreferencesLimits.maxTotalBytes ~/ 2);

      await prefs.setBytes('a', half);
      await prefs.setBytes('a', half);
      expect(
        () => prefs.setBytes('b', half),
        throwsA(isA<CloudPreferencesLimitException>()),
      );
      expect(prefs.containsKey('b'), isFalse);
      expect(store.values.containsKey('b'), isFalse);
    });
  });

  group('restore', () {
    test('fills only keys the app has not written', () async {
      final prefs = await CloudPreferences.getInstance();
      await prefs.setString('theme', 'light');
      final events = <CloudPreferencesRestoreEvent>[];
      prefs.onRestored.listen(events.add);

      store.emit(
        StoreChange(
          reason: StoreChangeReason.restored,
          keys: ['theme', 'count'],
          values: {'theme': 'dark', 'count': 7},
        ),
      );
      await pumpEventQueue();

      expect(prefs.getString('theme'), 'light');
      expect(prefs.getInt('count'), 7);
      expect(events.single.keys, {'count'});
    });

    test('does not emit when nothing was restored', () async {
      CloudPreferences.setMockStore(
        store = InMemoryCloudPreferencesStore({'theme': 'light'}),
      );
      final prefs = await CloudPreferences.getInstance();
      var emitted = false;
      prefs.onRestored.listen((_) => emitted = true);

      store.emit(
        StoreChange(
          reason: StoreChangeReason.restored,
          keys: ['theme'],
          values: {'theme': 'dark'},
        ),
      );
      await pumpEventQueue();
      expect(prefs.getString('theme'), 'light');
      expect(emitted, isFalse);
    });
  });

  group('live changes', () {
    test('applies changes and removals, and reports them', () async {
      CloudPreferences.setMockStore(
        store = InMemoryCloudPreferencesStore({'old': 'x'}),
      );
      final prefs = await CloudPreferences.getInstance(liveSync: true);
      final changes = <CloudPreferencesChange>[];
      prefs.changes.listen(changes.add);

      store.emit(
        StoreChange(
          reason: StoreChangeReason.serverChange,
          keys: ['old', 'theme'],
          values: {'theme': 'dark'},
        ),
      );
      await pumpEventQueue();

      expect(prefs.containsKey('old'), isFalse);
      expect(prefs.getString('theme'), 'dark');
      expect(changes.single.reason, CloudPreferencesChangeReason.serverChange);
      expect(changes.single.keys, {'old', 'theme'});
    });

    test('applies changes that arrive while the store is opening', () async {
      final slow = _SlowStore();
      CloudPreferences.setMockStore(slow);
      final opening = CloudPreferences.getInstance(liveSync: true);
      await pumpEventQueue();

      slow.emit(
        StoreChange(
          reason: StoreChangeReason.initialSync,
          keys: ['theme'],
          values: {'theme': 'dark'},
        ),
      );
      slow.finishOpening();
      final prefs = await opening;

      expect(prefs.getString('theme'), 'dark');
    });
  });
}

/// A store whose [initialize] waits until [finishOpening] is called.
class _SlowStore extends InMemoryCloudPreferencesStore {
  _SlowStore() : super({});

  final _opened = Completer<void>();

  void finishOpening() => _opened.complete();

  @override
  Future<Map<String, Object>> initialize({
    required bool liveSync,
    required Set<String> localOnlyKeys,
  }) async {
    await _opened.future;
    return super.initialize(liveSync: liveSync, localOnlyKeys: localOnlyKeys);
  }
}
