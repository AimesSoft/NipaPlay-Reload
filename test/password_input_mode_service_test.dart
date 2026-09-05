import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/password_input_mode_service.dart';

void main() {
  const channel = MethodChannel('nipaplay/password_input_mode');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS restricts only the focused password and restores on blur',
      (tester) async {
    final calls = <bool>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'setPasswordMode');
      expect(call.arguments, isA<bool>());
      calls.add(call.arguments as bool);
      return null;
    });
    final service = PasswordInputModeService()..start();
    final passwordFocus = FocusNode();
    final normalFocus = FocusNode();
    addTearDown(() {
      service.dispose();
      passwordFocus.dispose();
      normalFocus.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextField(focusNode: passwordFocus, obscureText: true),
      TextField(focusNode: normalFocus),
    ]))));
    await tester.pumpAndSettle();
    passwordFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);

    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);

    normalFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a revealed password stays in password input mode',
      (tester) async {
    final calls = <bool>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.arguments as bool);
      return null;
    });
    final service = PasswordInputModeService()..start();
    addTearDown(() {
      service.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: TextField(
      autofocus: true,
      obscureText: false,
      keyboardType: TextInputType.visiblePassword,
    ))));
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
