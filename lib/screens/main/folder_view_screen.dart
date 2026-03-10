import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../widgets/folder_view.dart';

/// Standalone page pushed on top of the nav stack (e.g. when viewing
/// a family member's folder). Takes [title], [folderPath], and [readOnly]
/// as constructor params.
class FolderViewScreen extends StatelessWidget {
  final String title;
  final String folderPath;
  final bool readOnly;

  const FolderViewScreen({
    super.key,
    required this.title,
    required this.folderPath,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title,
            style:
                GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FolderView(
        title: '',
        folderPath: folderPath,
        readOnly: readOnly,
        showHeader: false,
      ),
    );
  }
}
