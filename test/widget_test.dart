// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:areaguardian/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  SharedPreferences.setMockInitialValues({});

  testWidgets('monta la aplicación', (
    WidgetTester tester,
  ) async {
    await Firebase.initializeApp();
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AreaGuardianApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
