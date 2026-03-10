import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/io_client.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';

/// After the user connects their phone to the AiHomeCloud hotspot, this
/// screen lets them enter home Wi-Fi credentials.  On submit the backend
/// stores the credentials, tears down the hotspot, and connects to the
/// specified network (with retries).
class WifiSetupScreen extends ConsumerStatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  ConsumerState<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends ConsumerState<WifiSetupScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  bool _submitted = false;
  String? _error;
  bool _probing = true;
  String? _deviceIp;
  bool _obscurePassword = true;

  /// Common hotspot gateway IPs (NetworkManager, Android, etc.)
  static const _gatewayIps = [
    '10.42.0.1',    // NetworkManager default
    '192.168.4.1',  // some AP configs
    '192.168.43.1', // Android hotspot
    '192.168.1.1',  // common router
  ];

  @override
  void initState() {
    super.initState();
    _probeDevice();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Probe common hotspot gateway IPs to find the AiHomeCloud backend.
  Future<void> _probeDevice() async {
    setState(() {
      _probing = true;
      _error = null;
    });

    // Build an HTTP client that trusts any self-signed cert.
    final httpClient = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true
      ..connectionTimeout = const Duration(seconds: 3);
    final client = IOClient(httpClient);

    try {
      for (final ip in _gatewayIps) {
        try {
          final uri = Uri.parse('https://$ip:${AppConstants.apiPort}/');
          final res = await client.get(uri).timeout(
            const Duration(seconds: 4),
          );
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            final service = body['service'] as String?;
            if (service == 'AiHomeCloud' || service == 'CubieCloud') {
              if (mounted) {
                setState(() {
                  _deviceIp = ip;
                  _probing = false;
                });
              }
              return;
            }
          }
        } catch (_) {
          // Try next IP.
        }
      }

      if (mounted) {
        setState(() {
          _probing = false;
          _error = 'Could not find AiHomeCloud on the hotspot. '
              'Make sure you are connected to the "AiHomeCloud" Wi-Fi network.';
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _deviceIp == null) return;
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    // Call the unauthenticated setup endpoint on the device.
    final httpClient = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true
      ..connectionTimeout = const Duration(seconds: 5);
    final client = IOClient(httpClient);

    try {
      final uri = Uri.parse(
        'https://$_deviceIp:${AppConstants.apiPort}'
        '${AppConstants.apiVersion}/network/wifi/setup',
      );
      final res = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ssid': ssid, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _submitted = true;
          });
        }
        // After a delay, navigate back to scan screen.
        // The hotspot is going down so the phone will auto-reconnect to home Wi-Fi.
        await Future.delayed(const Duration(seconds: 8));
        if (mounted) {
          context.go('/scan-network');
        }
      } else {
        final body = _tryDecodeJson(res.body);
        final detail = body?['detail'] as String? ?? 'Setup failed (${res.statusCode}).';
        if (mounted) {
          setState(() {
            _submitting = false;
            _error = detail;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // A timeout or connection drop here is expected — the hotspot may
        // have shut down before the response could be fully delivered.
        if (e is TimeoutException || e is SocketException) {
          setState(() {
            _submitting = false;
            _submitted = true;
          });
          await Future.delayed(const Duration(seconds: 8));
          if (mounted) context.go('/scan-network');
        } else {
          setState(() {
            _submitting = false;
            _error = 'Setup failed: ${friendlyError(e)}';
          });
        }
      }
    } finally {
      client.close();
    }
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
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
            children: [
              const SizedBox(height: 24),

              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    onPressed: _submitting ? null : () => context.go('/hotspot-connect'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set Up Wi-Fi',
                      style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 8),

              Expanded(
                child: _submitted
                    ? _buildSubmittedView()
                    : _probing
                        ? _buildProbingView()
                        : _buildFormView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Probing ──────────────────────────────────────────────────────────────
  Widget _buildProbingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 20),
          Text(
            'Looking for AiHomeCloud on hotspot…',
            style: GoogleFonts.dmSans(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────
  Widget _buildFormView() {
    return ListView(
      children: [
        // Step badge
        _stepBadge('Step 2 of 2 — Enter your home Wi-Fi'),
        const SizedBox(height: 16),

        if (_deviceIp != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connected to AiHomeCloud at $_deviceIp',
                    style: GoogleFonts.dmSans(
                      color: AppColors.success,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Text(
          'Enter the Wi-Fi network credentials you want your '
          'AiHomeCloud to join. This can be your home Wi-Fi or '
          "your phone's mobile hotspot.",
          style: GoogleFonts.dmSans(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 24),

        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _ssidController,
                enabled: !_submitting,
                decoration: _inputDecoration(
                  label: 'Wi-Fi Network Name (SSID)',
                  icon: Icons.wifi_rounded,
                ),
                style: GoogleFonts.dmSans(color: AppColors.textPrimary),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'SSID is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                enabled: !_submitting,
                obscureText: _obscurePassword,
                decoration: _inputDecoration(
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),

        // Error
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.3)),
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
          if (_deviceIp == null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _probeDevice,
              child: Text(
                'Retry',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],

        const SizedBox(height: 28),

        // Submit
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                _submitting || _deviceIp == null ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Submit & Connect',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Submitted / waiting ──────────────────────────────────────────────────
  Widget _buildSubmittedView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 40,
            ),
          ).animate().scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1, 1),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: 24),
          Text(
            'Wi-Fi credentials sent!',
            style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'AiHomeCloud is connecting to your Wi-Fi.\n\n'
              'Switch back to your home Wi-Fi network — '
              'we\'ll take you to the scan screen in a moment.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: AppColors.primary),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _stepBadge(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.dmSans(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}
