import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers.dart';

class SetupCompleteScreen extends ConsumerStatefulWidget {
  const SetupCompleteScreen({super.key});

  @override
  ConsumerState<SetupCompleteScreen> createState() =>
      _SetupCompleteScreenState();
}

class _SetupCompleteScreenState extends ConsumerState<SetupCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final api = ref.read(apiServiceProvider);
      await api.createUser(
        _nameCtrl.text.trim(),
        _pinCtrl.text.isEmpty ? null : _pinCtrl.text,
      );

      // Get discovery state for the real device IP
      final discovery = ref.read(discoveryNotifierProvider);
      final deviceIp = discovery.deviceIp;
      if (deviceIp == null || deviceIp.isEmpty) {
        throw Exception('Device IP not found. Please restart setup.');
      }
      final previous = ref.read(authSessionProvider);

      final prefs = ref.read(sharedPreferencesProvider);
      if (_pinCtrl.text.isNotEmpty) {
        await prefs.setString(CubieConstants.prefUserPin, _pinCtrl.text);
      }
      await prefs.setString(
          CubieConstants.prefDeviceSerial,
          prefs.getString(CubieConstants.prefDeviceSerial) ?? '');
      await prefs.setString(CubieConstants.prefDeviceName, 'My AiHomeCloud');

      await ref.read(authSessionProvider.notifier).login(
            host: deviceIp,
            port: previous?.port ?? CubieConstants.apiPort,
            token: previous?.token ?? '',
            refreshToken: previous?.refreshToken,
            username: _nameCtrl.text.trim(),
            isAdmin: true,
          );

      ref.read(isSetupDoneProvider.notifier).state = true;

      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // Success badge
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: CubieColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: CubieColors.success, size: 36),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scale(
                        begin: const Offset(0.5, 0.5),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                        duration: 500.ms,
                      ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Text('Device Paired!',
                          style: GoogleFonts.sora(
                            color: CubieColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ))
                      .animate(delay: 200.ms)
                      .fadeIn(duration: 400.ms),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text("Let's set up your profile",
                          style: GoogleFonts.dmSans(
                              color: CubieColors.textSecondary, fontSize: 15))
                      .animate(delay: 300.ms)
                      .fadeIn(duration: 400.ms),
                ),

                const SizedBox(height: 48),

                // ── Name field ──────────────────────────────────────────────
                Text('Your Name',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600))
                    .animate(delay: 400.ms)
                    .fadeIn(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Dad, Mom, Alex…',
                    prefixIcon:
                        Icon(Icons.person_rounded, color: CubieColors.textMuted),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter your name'
                      : null,
                )
                    .animate(delay: 450.ms)
                    .fadeIn()
                    .slideX(begin: 0.05, end: 0),

                const SizedBox(height: 24),

                // ── PIN field ───────────────────────────────────────────────
                Text('PIN (Optional)',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600))
                    .animate(delay: 500.ms)
                    .fadeIn(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pinCtrl,
                  style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '4-digit PIN',
                    prefixIcon:
                        Icon(Icons.lock_rounded, color: CubieColors.textMuted),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 4) {
                      return 'PIN must be at least 4 digits';
                    }
                    return null;
                  },
                )
                    .animate(delay: 550.ms)
                    .fadeIn()
                    .slideX(begin: 0.05, end: 0),

                const SizedBox(height: 4),
                Text(
                  'A PIN adds a layer of privacy for your personal folder.',
                  style:
                      GoogleFonts.dmSans(color: CubieColors.textMuted, fontSize: 12),
                ).animate(delay: 600.ms).fadeIn(),

                const SizedBox(height: 48),

                // ── Submit ──────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: CubieColors.background),
                          )
                        : Text('Get Started',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                )
                    .animate(delay: 650.ms)
                    .fadeIn()
                    .slideY(begin: 0.2, end: 0),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
