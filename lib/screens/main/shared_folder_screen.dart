import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../widgets/cubie_card.dart';
import '../../widgets/folder_view.dart';

/// Tab 4 — shared folder browser with a DLNA / SMB info card at the top.
class SharedFolderScreen extends StatelessWidget {
  const SharedFolderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('Shared',
                  style: GoogleFonts.sora(
                      color: CubieColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ).animate().fadeIn(duration: 400.ms),

            // ── DLNA / Samba info card ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: CubieCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: CubieColors.secondary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.devices_rounded,
                          color: CubieColors.secondary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Network Access',
                              style: GoogleFonts.dmSans(
                                  color: CubieColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            'TV & Computer Sharing  •  Smart TV Streaming',
                            style: GoogleFonts.dmSans(
                                color: CubieColors.textSecondary,
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.info_outline_rounded,
                        color: CubieColors.textMuted, size: 18),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0),
            ),

            // ── Shared folder view ──────────────────────────────────────────
            const Expanded(
              child: FolderView(
                title: '',
                folderPath: CubieConstants.sharedPath,
                readOnly: false,
                showHeader: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
