import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../models/backup_models.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../services/api_service.dart';
import '../../services/backup_runner.dart';
import '../../services/backup_worker.dart';
import '../../widgets/app_card.dart';

/// Screen for managing automatic phone-to-NAS photo backup.
///
/// Entry point: More tab → Auto Backup tile.
/// Shows empty state / setup flow (bottom sheet) / active job list.
class AutoBackupScreen extends ConsumerStatefulWidget {
  const AutoBackupScreen({super.key});

  @override
  ConsumerState<AutoBackupScreen> createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends ConsumerState<AutoBackupScreen> {
  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(backupStatusProvider);
    final progress = ref.watch(backupProgressProvider);

    // Auto-refresh job stats (total counts) after a manual backup completes.
    ref.listen<BackupProgress>(backupProgressProvider, (prev, next) {
      if (next.phase == BackupPhase.done &&
          prev?.phase == BackupPhase.running) {
        ref.invalidate(backupStatusProvider);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Auto Backup',
          style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
      ),
      body: statusAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Text(friendlyError(e),
              style: GoogleFonts.dmSans(
                  color: AppColors.textMuted, fontSize: 14)),
        ),
        data: (status) => status.jobs.isEmpty
            ? _EmptyState(onSetup: () => _openSetupSheet(context))
            : _ActiveState(
                status: status,
                progress: progress,
                onAddFolder: () => _openSetupSheet(context),
                onBackUpNow: _triggerImmediateBackup,
                onDeleteJob: _deleteJob,
              ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openSetupSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SetupSheet(
        onConfirm: (phoneFolder, destination) async {
          Navigator.of(ctx).pop();
          await _createJob(phoneFolder, destination);
        },
      ),
    );
  }

  Future<void> _createJob(String phoneFolder, String destination) async {
    try {
      await ref.read(apiServiceProvider).createBackupJob(phoneFolder, destination);
      ref.invalidate(backupStatusProvider);
      // Trigger an immediate backup run after setup
      await BackupWorker.instance.triggerImmediate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup set up — syncing now over WiFi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _deleteJob(String jobId) async {
    try {
      await ref.read(apiServiceProvider).deleteBackupJob(jobId);
      ref.invalidate(backupStatusProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _triggerImmediateBackup() {
    final status = ref.read(backupStatusProvider).valueOrNull;
    if (status == null || status.jobs.isEmpty) return;
    final username = ref.read(authSessionProvider)?.username ?? '';
    ref
        .read(backupProgressProvider.notifier)
        .startAll(status.jobs, username);
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onSetup;

  const _EmptyState({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_upload_rounded,
                color: AppColors.primary, size: 40),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            'Back up your photos automatically',
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 12),
          Text(
            'Select folders on your phone and they\'ll be safely copied to your AiHomeCloud — over WiFi, in the background.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ).animate().fadeIn(delay: 150.ms),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Set up backup',
                style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),
        ],
      ),
    );
  }
}

// ── Active state ──────────────────────────────────────────────────────────────

class _ActiveState extends StatelessWidget {
  final BackupStatus status;
  final BackupProgress progress;
  final VoidCallback onAddFolder;
  final VoidCallback onBackUpNow;
  final Future<void> Function(String jobId) onDeleteJob;

  const _ActiveState({
    required this.status,
    required this.progress,
    required this.onAddFolder,
    required this.onBackUpNow,
    required this.onDeleteJob,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ...status.jobs.asMap().entries.map((entry) {
          final i = entry.key;
          final job = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _JobCard(
              job: job,
              onDelete: () => _confirmDelete(context, job, onDeleteJob),
            ).animate().fadeIn(delay: (i * 60).ms),
          );
        }),

        // Live progress card — visible while backing up or just after done.
        if (progress.phase != BackupPhase.idle) ...[          
          const SizedBox(height: 4),
          _BackupProgressCard(progress: progress),
          const SizedBox(height: 4),
        ],

        const SizedBox(height: 8),

        // Back up now
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: progress.isActive ? null : onBackUpNow,
            icon: progress.isActive
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.sync_rounded,
                    size: 18, color: AppColors.primary),
            label: Text(
              progress.isActive ? 'Backing up…' : 'Back up now',
              style: GoogleFonts.dmSans(
                  color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Add another folder
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onAddFolder,
            icon: const Icon(Icons.add_rounded,
                size: 18, color: AppColors.textSecondary),
            label: Text(
              'Add another folder',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // WiFi-only notice
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_rounded,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              'Runs on WiFi only — your mobile data is protected.',
              style: GoogleFonts.dmSans(
                  color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  static void _confirmDelete(
    BuildContext context,
    BackupJob job,
    Future<void> Function(String) onDelete,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove backup?', style: GoogleFonts.sora()),
        content: Text(
          'Stop backing up "${job.folderDisplayName}" to ${job.destinationLabel}?',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(job.id);
            },
            child: Text('Remove',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final BackupJob job;
  final VoidCallback onDelete;

  const _JobCard({required this.job, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.folder_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      job.folderDisplayName,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        job.destinationLabel,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${job.lastSyncRelative} · ${job.totalUploaded} files backed up',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Backup progress card ──────────────────────────────────────────────────────

class _BackupProgressCard extends StatelessWidget {
  final BackupProgress progress;

  const _BackupProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final isActive = progress.isActive;
    final isDone = progress.phase == BackupPhase.done;
    final isFailed = progress.phase == BackupPhase.failed;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isActive)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              else if (isDone)
                const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 17)
              else if (isFailed)
                const Icon(Icons.error_rounded,
                    color: AppColors.error, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.statusLine,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (progress.speedText != null) ...[
                const SizedBox(width: 8),
                Text(
                  progress.speedText!,
                  style: GoogleFonts.dmSans(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (progress.phase == BackupPhase.running &&
              progress.totalFiles > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.totalFiles > 0
                    ? progress.doneFiles / progress.totalFiles
                    : null,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 4,
              ),
            ),
            if (progress.currentFile != null) ...[
              const SizedBox(height: 5),
              Text(
                progress.currentFile!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ] else if (progress.phase == BackupPhase.scanning) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Setup bottom sheet ────────────────────────────────────────────────────────

class _SetupSheet extends StatefulWidget {
  final Future<void> Function(String phoneFolder, String destination) onConfirm;

  const _SetupSheet({required this.onConfirm});

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  int _step = 0;
  String? _selectedFolder;
  String? _selectedDestination;
  bool _wifiOnly = true;
  bool _submitting = false;

  // ── Step 1: Folder picker ──────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select a folder to back up',
    );
    if (path != null && mounted) {
      setState(() {
        _selectedFolder = path;
        _step = 1;
      });
    }
  }

  String get _folderDisplayName {
    if (_selectedFolder == null) return '';
    final parts = _selectedFolder!.split(RegExp(r'[/\\]'));
    return parts.lastWhere((s) => s.isNotEmpty,
        orElse: () => _selectedFolder!);
  }

  // ── Step 2 → Step 3 ────────────────────────────────────────────────────────

  void _selectDestination(String dest) {
    setState(() {
      _selectedDestination = dest;
      _step = 2;
    });
  }

  // ── Confirm ────────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_selectedFolder == null || _selectedDestination == null) return;
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(_selectedFolder!, _selectedDestination!);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _step == 0
                ? _buildStepFolder()
                : _step == 1
                    ? _buildStepDestination()
                    : _buildStepConfirm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          text,
          style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
      );

  // Step 1 — pick phone folder
  Widget _buildStepFolder() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSheetTitle('Which folder on your phone?'),
        Text(
          'Select the folder containing the photos and videos you want to back up.',
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 20),
            label: Text(
              'Browse phone folders',
              style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // Step 2 — pick NAS destination
  Widget _buildStepDestination() {
    final destinations = [
      (
        value: 'personal',
        title: 'My Personal Files',
        subtitle: 'Only you can see these',
        icon: Icons.person_rounded,
        color: AppColors.primary,
      ),
      (
        value: 'family',
        title: 'Family Folder',
        subtitle: 'Shared with everyone',
        icon: Icons.people_rounded,
        color: const Color(0xFFE8A84C),
      ),
      (
        value: 'entertainment',
        title: 'Entertainment',
        subtitle: 'Movies and videos',
        icon: Icons.movie_rounded,
        color: AppColors.secondary,
      ),
    ];

    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textMuted, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildSheetTitle('Where should it go?')),
          ],
        ),
        Text(
          '"$_folderDisplayName" will back up to:',
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...destinations.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DestinationCard(
                title: d.title,
                subtitle: d.subtitle,
                icon: d.icon,
                color: d.color,
                onTap: () => _selectDestination(d.value),
              ),
            )),
      ],
    );
  }

  // Step 3 — confirm
  Widget _buildStepConfirm() {
    final destLabel = _selectedDestination == 'personal'
        ? 'Your Personal Files'
        : _selectedDestination == 'family'
            ? 'Family Folder'
            : 'Entertainment';

    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _step = 1),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textMuted, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildSheetTitle('Ready to start')),
          ],
        ),

        // Summary
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.folder_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                _folderDisplayName,
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.textMuted),
              ),
              Flexible(
                child: Text(
                  destLabel,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // WiFi-only toggle
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'WiFi only',
              style: GoogleFonts.dmSans(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Recommended — protects you from mobile data charges',
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
            value: _wifiOnly,
            activeThumbColor: AppColors.primary,
            onChanged: (v) {
              // Warn if the user tries to disable WiFi-only
              if (!v) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Use mobile data?', style: GoogleFonts.sora()),
                    content: Text(
                      'Backing up photos over mobile data can use a lot of data and may incur charges.',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Keep WiFi only',
                            style: GoogleFonts.dmSans(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _wifiOnly = false);
                          Navigator.pop(ctx);
                        },
                        child: Text('Allow mobile data',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                );
              } else {
                setState(() => _wifiOnly = true);
              }
            },
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Start backup',
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Destination card ──────────────────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DestinationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
