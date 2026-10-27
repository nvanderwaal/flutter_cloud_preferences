import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_preferences/flutter_cloud_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await CloudPreferences.getInstance();
  runApp(ExampleApp(prefs: prefs));
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, required this.prefs});

  final CloudPreferences prefs;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final StreamSubscription<CloudPreferencesRestoreEvent> _restored;

  CloudPreferences get _prefs => widget.prefs;
  bool get _darkMode => _prefs.getBool('darkMode') ?? false;
  int get _counter => _prefs.getInt('counter') ?? 0;

  @override
  void initState() {
    super.initState();
    // On a fresh iOS or macOS install, iCloud values can arrive after start-up.
    _restored = _prefs.onRestored.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _restored.cancel();
    super.dispose();
  }

  Future<void> _update(Future<void> Function() write) async {
    final future = write();
    setState(() {});
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(),
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_cloud_preferences')),
        body: ListView(
          children: [
            SwitchListTile(
              title: const Text('Dark mode'),
              value: _darkMode,
              onChanged: (value) =>
                  _update(() => _prefs.setBool('darkMode', value)),
            ),
            ListTile(
              title: const Text('Counter'),
              subtitle: Text('$_counter'),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Increment',
                onPressed: () =>
                    _update(() => _prefs.setInt('counter', _counter + 1)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Change the values, then delete and reinstall the app. '
                'They come back from iCloud or Android Auto Backup.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
