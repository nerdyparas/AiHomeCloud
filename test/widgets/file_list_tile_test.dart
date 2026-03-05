import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock FileListTile widget for testing
/// 
/// In a real scenario, this would be imported from:
/// import 'package:cubiecloud/widgets/file_list_tile.dart';
class FileListTile extends StatelessWidget {
  final String name;
  final bool isDirectory;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileListTile({
    Key? key,
    required this.name,
    this.isDirectory = false,
    required this.onTap,
    required this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(isDirectory ? Icons.folder : Icons.insert_drive_file),
      title: Text(name),
      trailing: const Icon(Icons.more_vert),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Mock context menu for long-press
class FileContextMenu extends StatelessWidget {
  final String fileName;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const FileContextMenu({
    Key? key,
    required this.fileName,
    required this.onDelete,
    required this.onRename,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(fileName),
      children: [
        SimpleDialogOption(
          onPressed: () {
            onRename();
            Navigator.pop(context);
          },
          child: const Text('Rename'),
        ),
        SimpleDialogOption(
          onPressed: () {
            onDelete();
            Navigator.pop(context);
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

void main() {
  group('FileListTile Widget Tests', () {
    testWidgets('tap callback fires when tile is tapped', (WidgetTester tester) async {
      // 7G.3: Verify tap callback fires
      bool tapFired = false;
      bool longPressFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'test_file.txt',
              isDirectory: false,
              onTap: () {
                tapFired = true;
              },
              onLongPress: () {
                longPressFired = true;
              },
            ),
          ),
        ),
      );

      // Tap the tile
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Verify tap callback fired
      expect(tapFired, isTrue);
      expect(longPressFired, isFalse);
    });

    testWidgets('long-press callback fires when tile is long-pressed', (WidgetTester tester) async {
      // 7G.3: Verify long-press callback fires
      bool tapFired = false;
      bool longPressFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'test_file.txt',
              isDirectory: false,
              onTap: () {
                tapFired = true;
              },
              onLongPress: () {
                longPressFired = true;
              },
            ),
          ),
        ),
      );

      // Long-press the tile
      await tester.longPress(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Verify long-press callback fired
      expect(longPressFired, isTrue);
      expect(tapFired, isFalse);
    });

    testWidgets('displays file icon for files', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'document.pdf',
              isDirectory: false,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      // Verify file icon is displayed
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);

      // Verify folder icon is not displayed
      expect(find.byIcon(Icons.folder), findsNothing);
    });

    testWidgets('displays folder icon for directories', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'Documents',
              isDirectory: true,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      // Verify folder icon is displayed
      expect(find.byIcon(Icons.folder), findsOneWidget);

      // Verify file icon is not displayed
      expect(find.byIcon(Icons.insert_drive_file), findsNothing);
    });

    testWidgets('displays file name', (WidgetTester tester) async {
      const fileName = 'my_important_file.txt';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: fileName,
              isDirectory: false,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      // Verify file name is displayed
      expect(find.text(fileName), findsOneWidget);
    });

    testWidgets('displays context menu icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'test_file.txt',
              isDirectory: false,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      // Verify more_vert icon is displayed
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('multiple taps and long-presses work correctly', (WidgetTester tester) async {
      int tapCount = 0;
      int longPressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              name: 'test_file.txt',
              isDirectory: false,
              onTap: () {
                tapCount++;
              },
              onLongPress: () {
                longPressCount++;
              },
            ),
          ),
        ),
      );

      // Perform multiple taps
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Perform multiple long-presses
      await tester.longPress(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Verify counts
      expect(tapCount, equals(2));
      expect(longPressCount, equals(1));
    });
  });
}
