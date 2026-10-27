// Runs against the real native store on a device, simulator or desktop:
// flutter test integration_test

import 'dart:typed_data';

import 'package:flutter_cloud_preferences/flutter_cloud_preferences.dart';
import 'package:flutter_cloud_preferences/src/platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Drops the Dart cache so the next [CloudPreferences.getInstance] reads every
/// value back from the native store.
Future<CloudPreferences> reload() {
  CloudPreferences.setMockStore(PigeonCloudPreferencesStore());
  return CloudPreferences.getInstance();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await (await reload()).clear();
  });

  testWidgets('round-trips every type through the native store', (
    tester,
  ) async {
    final prefs = await CloudPreferences.getInstance();
    await prefs.setString('string', 'value');
    await prefs.setBool('bool', true);
    await prefs.setInt('int', 1 << 40);
    await prefs.setInt('smallInt', 3);
    await prefs.setDouble('double', 1.5);
    await prefs.setDouble('wholeDouble', 2.0);
    await prefs.setStringList('list', ['b', 'a', 'b']);
    await prefs.setStringList('emptyList', []);
    await prefs.setBytes('bytes', Uint8List.fromList([0, 1, 255]));

    final reloaded = await reload();

    expect(reloaded.getString('string'), 'value');
    expect(reloaded.getBool('bool'), isTrue);
    expect(reloaded.getInt('int'), 1 << 40);
    expect(reloaded.getInt('smallInt'), 3);
    expect(reloaded.getDouble('double'), 1.5);
    expect(reloaded.getDouble('wholeDouble'), 2.0);
    expect(reloaded.getStringList('list'), ['b', 'a', 'b']);
    expect(reloaded.getStringList('emptyList'), isEmpty);
    expect(reloaded.getBytes('bytes'), [0, 1, 255]);
  });

  testWidgets('removes and clears in the native store', (tester) async {
    final prefs = await CloudPreferences.getInstance();
    await prefs.setString('a', 'x');
    await prefs.setString('b', 'y');

    await prefs.remove('a');
    expect((await reload()).getKeys(), {'b'});

    await (await CloudPreferences.getInstance()).clear();
    expect((await reload()).getKeys(), isEmpty);
  });
}
