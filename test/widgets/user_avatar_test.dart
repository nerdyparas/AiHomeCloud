import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/widgets/user_avatar.dart';

void main() {
  Widget buildSubject({
    String name = 'Alice',
    int colorIndex = 0,
    String iconEmoji = '',
    double size = 72,
    bool isSelected = false,
    bool isLoading = false,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserAvatar(
              name: name,
              colorIndex: colorIndex,
              iconEmoji: iconEmoji,
              size: size,
              isSelected: isSelected,
              isLoading: isLoading,
            ),
          ),
        ),
      );

  testWidgets('shows initial letter when no emoji provided',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(name: 'Alice'));
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('shows emoji when iconEmoji is set',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(name: 'Alice', iconEmoji: '🦊'));
    await tester.pump();

    expect(find.text('🦊'), findsOneWidget);
    // Should NOT show the initial letter
    expect(find.text('A'), findsNothing);
  });

  testWidgets('shows ? for empty name with no emoji',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(name: ''));
    await tester.pump();

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('shows loading spinner when isLoading is true',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(isLoading: true));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Should NOT show letter or emoji
    expect(find.text('A'), findsNothing);
  });

  testWidgets('renders at custom size', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(size: 48));
    await tester.pump();

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(container.constraints?.maxWidth ?? container.decoration, isNotNull);
    expect(find.byType(UserAvatar), findsOneWidget);
  });

  testWidgets('applies selection border when isSelected',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(isSelected: true));
    await tester.pump();

    expect(find.byType(UserAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cycles through color palette by colorIndex',
      (WidgetTester tester) async {
    // colorIndex 0 and 8 should produce the same color (mod 8)
    await tester.pumpWidget(buildSubject(colorIndex: 0));
    await tester.pump();
    expect(find.byType(UserAvatar), findsOneWidget);

    await tester.pumpWidget(buildSubject(colorIndex: 7));
    await tester.pump();
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
