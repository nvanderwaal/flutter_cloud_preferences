import 'package:flutter_cloud_preferences/flutter_cloud_preferences.dart';
import 'package:flutter_cloud_preferences_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('increments and stores the counter', (tester) async {
    CloudPreferences.setMockInitialValues({'counter': 2});
    final prefs = await CloudPreferences.getInstance();

    await tester.pumpWidget(ExampleApp(prefs: prefs));
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Increment'));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(prefs.getInt('counter'), 3);
  });
}
