import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infoapp/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('infoapp/app_launcher');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getInstalledApps':
            case 'getSavedApps':
              return <String>[];
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows InfoApp home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const InfoApp());
    await tester.pump();

    expect(find.text('InfoApp'), findsOneWidget);
    expect(find.text('ERP modular'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
  });
}
