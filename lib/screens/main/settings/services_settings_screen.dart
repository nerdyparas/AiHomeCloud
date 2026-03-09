import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../core/error_utils.dart';
import '../../../models/models.dart';
import '../../../providers.dart';
import '../../../widgets/cubie_card.dart';

class ServicesSettingsScreen extends ConsumerWidget {
  const ServicesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        backgroundColor: CubieColors.background,
        title: Text('Sharing & Streaming',
            style: GoogleFonts.sora(
                color: CubieColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: CubieColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: servicesAsync.when(
        data: (services) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (int i = 0; i < services.length; i++) ...[
                    _ServiceToggle(
                      service: services[i],
                      onToggle: (v) async {
                        await ref
                            .read(apiServiceProvider)
                            .toggleService(services[i].id, v);
                        ref.invalidate(servicesProvider);
                      },
                    ),
                    if (i < services.length - 1)
                      const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: CubieColors.cardBorder),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 24),
          ],
        ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: CubieColors.primary)),
        error: (e, _) => Center(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(friendlyError(e),
              style: const TextStyle(color: CubieColors.error)),
        )),
      ),
    );
  }
}

// ─── Service toggle row ─────────────────────────────────────────────────────

class _ServiceToggle extends StatefulWidget {
  final ServiceInfo service;
  final ValueChanged<bool> onToggle;
  const _ServiceToggle({required this.service, required this.onToggle});

  @override
  State<_ServiceToggle> createState() => _ServiceToggleState();
}

class _ServiceToggleState extends State<_ServiceToggle> {
  late bool _on;

  @override
  void initState() {
    super.initState();
    _on = widget.service.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (_on ? CubieColors.primary : CubieColors.textMuted)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.service.icon,
                color: _on ? CubieColors.primary : CubieColors.textMuted,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_friendlyServiceName(widget.service.id),
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Text(widget.service.description,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: _on,
            onChanged: (v) {
              setState(() => _on = v);
              widget.onToggle(v);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Friendly service name mapping ──────────────────────────────────────────

String _friendlyServiceName(String id) => switch (id.toLowerCase()) {
      'samba' || 'smb' => 'TV & Computer Sharing',
      'dlna' => 'Smart TV Streaming',
      'nfs' => 'Network Sharing',
      'ssh' => 'Remote Access (Advanced)',
      _ => id,
    };
