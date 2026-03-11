import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/core_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/folder_view.dart';

/// Tab 2 — Files explorer with two root entries: personal folder and Shared.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  // null = root view, non-null = inside a folder
  String? _currentPath;
  String? _currentTitle;

  void _openFolder(String path, String title) {
    setState(() {
      _currentPath = path;
      _currentTitle = title;
    });
  }

  void _goBack() {
    setState(() {
      _currentPath = null;
      _currentTitle = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPath != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: FolderView(
          title: _currentTitle ?? 'Files',
          folderPath: _currentPath!,
          readOnly: false,
          showHeader: true,
          onBack: _goBack,
        ),
      );
    }

    // Root view: show 2 folder entries
    final session = ref.watch(authSessionProvider);
    final username = session?.username ?? 'My Files';
    final personalPath = '${AppConstants.personalBasePath}$username/';
    const sharedPath = AppConstants.sharedPath;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text('Files',
                style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FolderCard(
                    name: username,
                    icon: Icons.person_rounded,
                    color: AppColors.primary,
                    onTap: () => _openFolder(personalPath, username),
                  ),
                  const SizedBox(height: 12),
                  _FolderCard(
                    name: 'Shared',
                    icon: Icons.people_rounded,
                    color: AppColors.secondary,
                    onTap: () => _openFolder(sharedPath, 'Shared'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FolderCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(name,
          style: GoogleFonts.dmSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          )),
        trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
