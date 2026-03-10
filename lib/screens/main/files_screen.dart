import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../widgets/folder_view.dart';
import 'my_folder_screen.dart';
import 'shared_folder_screen.dart';

/// Tab 2 — Files hub with three segments: My Files | Shared | Videos.
///
/// Uses IndexedStack so each segment preserves its scroll position and
/// keeps its internal state when switching between segments.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  int _segment = 0;

  static const _labels = ['My Files', 'Shared', 'Videos'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header + segment control ─────────────────────────────────────
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Files',
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 14),
                _SegmentBar(
                  labels: _labels,
                  selected: _segment,
                  onTap: (i) => setState(() => _segment = i),
                ),
              ],
            ),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: [
              // My Files
              const _KeepAliveChild(child: _MyFilesBody()),
              // Shared
              const _KeepAliveChild(child: _SharedBody()),
              // Videos
              _KeepAliveChild(
                child: FolderView(
                  title: 'Videos',
                  folderPath: '${AppConstants.sharedPath}Videos/',
                  readOnly: false,
                  showHeader: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Segment bar ────────────────────────────────────────────────────────────

class _SegmentBar extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  const _SegmentBar({
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: GoogleFonts.dmSans(
                        color: selected == i
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: selected == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Keep-alive wrapper ──────────────────────────────────────────────────────

class _KeepAliveChild extends StatefulWidget {
  final Widget child;
  const _KeepAliveChild({required this.child});

  @override
  State<_KeepAliveChild> createState() => _KeepAliveChildState();
}

class _KeepAliveChildState extends State<_KeepAliveChild>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ─── Body widgets (Scaffold-free wrappers around existing screens) ───────────

/// Renders the body of MyFolderScreen without a Scaffold wrapper.
/// We re-use MyFolderScreen directly via the IndexedStack — it creates its
/// own internal Scaffold for SafeArea, background colour, and scroll.
class _MyFilesBody extends StatelessWidget {
  const _MyFilesBody();

  @override
  Widget build(BuildContext context) => const MyFolderScreen();
}

class _SharedBody extends StatelessWidget {
  const _SharedBody();

  @override
  Widget build(BuildContext context) => const SharedFolderScreen();
}
