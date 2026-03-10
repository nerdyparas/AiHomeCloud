import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../services/network_scanner.dart';

class NetworkScanScreen extends ConsumerStatefulWidget {
  const NetworkScanScreen({super.key});

  @override
  ConsumerState<NetworkScanScreen> createState() => _NetworkScanScreenState();
}

class _NetworkScanScreenState extends ConsumerState<NetworkScanScreen> {
  final _scanner = NetworkScanner.instance;
  final _hosts = <DiscoveredHost>[];
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingIp;
  double _progress = 0;
  String? _localIp;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _hosts.clear();
      _scanning = true;
      _progress = 0;
      _error = null;
    });

    _localIp = await _scanner.getLocalIp();
    if (_localIp == null) {
      setState(() {
        _scanning = false;
        _error = 'Could not detect local network. '
            'Make sure you are connected to Wi-Fi.';
      });
      return;
    }

    final stream = _scanner.scanNetwork(
      onProgress: (scanned, total) {
        if (mounted) {
          setState(() => _progress = scanned / total);
        }
      },
    );

    await for (final host in stream) {
      if (!mounted) return;
      setState(() {
        _hosts.add(host);
      });
    }

    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _selectDevice(DiscoveredHost host) async {
    if (_connecting) return;

    setState(() {
      _connecting = true;
      _connectingIp = host.ip;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);

      // Fetch pairing info from the discovered device
      final pairingInfo = await api.fetchPairingInfo(host.ip);
      final serial = pairingInfo['serial'] as String;
      final key = pairingInfo['key'] as String? ?? '';

      // Pair with the device
      final token = await api.pairDevice(
        serial,
        key,
        hostOverride: host.ip,
      );

      // Log in via auth session
      await ref.read(authSessionProvider.notifier).login(
            host: host.ip,
            port: AppConstants.apiPort,
            token: token,
            refreshToken: null,
            username: '',
            isAdmin: true,
          );

      // Fetch and persist TLS fingerprint
      try {
        final fingerprint = await api.fetchServerFingerprint(
          host: host.ip,
          port: AppConstants.apiPort,
        );
        if (fingerprint != null) {
          await persistServerFingerprint(ref, fingerprint);
        }
      } catch (_) {
        // Non-fatal — pinning can happen later
      }

      if (!mounted) return;

      // If already set up, go straight to dashboard; otherwise create profile
      final isSetupDone = ref.read(isSetupDoneProvider);
      context.go(isSetupDone ? '/dashboard' : '/setup');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectingIp = null;
        _error = 'Connection failed: ${friendlyError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Icon(
                      Icons.wifi_find_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find Your AiHomeCloud',
                          style: GoogleFonts.sora(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_localIp != null)
                          Text(
                            'Your network: $_localIp',
                            style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_scanning)
                    IconButton(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh_rounded),
                      color: AppColors.primary,
                      tooltip: 'Rescan',
                    ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 16),

              // Progress bar
              if (_scanning)
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: AppColors.card,
                        color: AppColors.primary,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).toInt()}% — scanning network…',
                      style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

              if (!_scanning && _hosts.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No devices found on the network.',
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),

              // Error
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.dmSans(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Device list
              Expanded(
                child: ListView(
                  children: [
                    if (_hosts.isNotEmpty) ...[
                      _sectionHeader('Devices Found'),
                      const SizedBox(height: 8),
                      ..._hosts.map((h) => _DeviceTile(
                            host: h,
                            isConnecting: _connectingIp == h.ip,
                            onTap: () => _selectDevice(h),
                          ).animate().fadeIn(duration: 300.ms).slideX(
                              begin: 0.05, end: 0)),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),

              // Bottom actions
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/qr-scan'),
                        icon: const Icon(Icons.qr_code_scanner_rounded,
                            size: 18),
                        label: Text(
                          'Scan QR Instead',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(
                              color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.sora(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DiscoveredHost host;
  final bool isConnecting;
  final VoidCallback? onTap;

  const _DeviceTile({
    required this.host,
    required this.isConnecting,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isConnecting ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        host.deviceName ?? 'AiHomeCloud',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        host.ip,
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action
                if (!isConnecting)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Connect',
                      style: GoogleFonts.dmSans(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isConnecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
