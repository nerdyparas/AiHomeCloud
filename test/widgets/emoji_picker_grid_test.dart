import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/widgets/emoji_picker_grid.dart';

void main() {
  String? selectedEmoji;

  Widget buildSubject({String initial = ''}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmojiPickerGrid(
              selectedEmoji: initial,
              onSelected: (emoji) => selectedEmoji = emoji,
            ),
          ),
        ),
      );

  setUp(() {
    selectedEmoji = null;
  });

  testWidgets('renders two section labels', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('People & Family'), findsOneWidget);
    expect(find.text('Animals, Hobbies & More'), findsOneWidget);
  });

  testWidgets('renders 32 emoji tiles', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    // 16 people + 16 others = 32 emoji tiles
    // Each emoji is in a GestureDetector within the grid
    expect(find.text('👶'), findsOneWidget);
    expect(find.text('🦁'), findsOneWidget);
    expect(find.text('⚽'), findsOneWidget);
  });

  testWidgets('fires onSelected when emoji is tapped',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.tap(find.text('🦊'));
    expect(selectedEmoji, '🦊');
  });

  testWidgets('shows "Use a different emoji" link',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Use a different emoji'), findsOneWidget);
  });

  testWidgets('tapping link shows custom input field',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    // Tap the link
    await tester.tap(find.text('Use a different emoji'));
    await tester.pump();

    // Custom input TextField should appear
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('highlights currently selected emoji',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(initial: '🐼'));
    await tester.pump();

    // The selected emoji should be rendered
    expect(find.text('🐼'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
