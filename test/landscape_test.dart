import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/core/widgets/feature_placeholder.dart';

void main() {
  testWidgets('FeaturePlaceholder renders in short landscape viewport',
      (tester) async {
    // Landscape phone: ~360-412 dp tall.
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeaturePlaceholder(
            icon: Icons.bar_chart,
            title: 'Reports',
            description: 'Test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Content is present and scrollable (no overflow exception).
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
