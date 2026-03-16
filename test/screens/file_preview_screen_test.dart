import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/main/file_preview_screen.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildSubject(FileItem file, [List<Override> overrides = const []]) =>
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: MaterialApp(home: FilePreviewScreen(file: file)),
      );

  // FilePreviewScreen reads apiServiceProvider in initState for getDownloadUrl
  // and authHeaders. For non-text files, _loading is set to false immediately.
  // The singleton ApiService is always available, just returns empty URLs.

  testWidgets('renders video file preview without crashing',
      (WidgetTester tester) async {
    final videoFile = FileItem(
      name: 'clip.mp4',
      path: '/personal/alice/Videos/clip.mp4',
      isDirectory: false,
      sizeBytes: 104857600,
      modified: DateTime(2026, 3, 1),
    );
    await tester.pumpWidget(buildSubject(videoFile));
    await tester.pump();

    expect(find.byType(FilePreviewScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders image file preview without crashing',
      (WidgetTester tester) async {
    final imageFile = FileItem(
      name: 'photo.jpg',
      path: '/personal/alice/Photos/photo.jpg',
      isDirectory: false,
      sizeBytes: 2048000,
      modified: DateTime(2026, 2, 15),
    );
    await tester.pumpWidget(buildSubject(imageFile));
    await tester.pump();

    expect(find.byType(FilePreviewScreen), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders audio file preview without crashing',
      (WidgetTester tester) async {
    final audioFile = FileItem(
      name: 'song.mp3',
      path: '/personal/alice/Music/song.mp3',
      isDirectory: false,
      sizeBytes: 5242880,
      modified: DateTime(2026, 1, 10),
    );
    await tester.pumpWidget(buildSubject(audioFile));
    await tester.pump();

    expect(find.byType(FilePreviewScreen), findsOneWidget);
    expect(find.text('song.mp3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows filename in AppBar title',
      (WidgetTester tester) async {
    final file = FileItem(
      name: 'document.pdf',
      path: '/personal/alice/Documents/document.pdf',
      isDirectory: false,
      sizeBytes: 1024,
      modified: DateTime(2026, 3, 10),
    );
    await tester.pumpWidget(buildSubject(file));
    await tester.pump();

    expect(find.text('document.pdf'), findsOneWidget);
  });
}
