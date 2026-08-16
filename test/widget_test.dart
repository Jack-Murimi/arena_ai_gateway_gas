import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/features/auth/login_screen.dart';

void main() {
  testWidgets('Login screen renders brand and form fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Gateway Gas Enterprises'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    // Tapping sign in with empty fields shows validation errors.
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
