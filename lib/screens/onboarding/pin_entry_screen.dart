import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers/core_providers.dart';
import '../../services/api_service.dart';

class PinEntryScreen extends ConsumerStatefulWidget {
  final String deviceIp;
  const PinEntryScreen({super.key, required this.deviceIp});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<String> _userNames = [];
  String? _selectedUser;
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final api = ApiService.instance;
      final names = await api.fetchUserNames(widget.deviceIp);
      if (!mounted) return;
      setState(() {
        _userNames = names;
        _selectedUser = names.isNotEmpty ? names.first : null;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty || _selectedUser == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiService.instance;
      final result = await api.loginWithPin(
        widget.deviceIp,
        _selectedUser!,
        pin,
      );

      final accessToken = result['accessToken'] as String;
      final refreshToken = result['refreshToken'] as String?;
      final user = result['user'] as Map<String, dynamic>;

      await ref.read(authSessionProvider.notifier).login(
            host: widget.deviceIp,
            port: AppConstants.apiPort,
            token: accessToken,
            refreshToken: refreshToken,
            username: user['name'] as String? ?? 'admin',
            isAdmin: user['isAdmin'] as bool? ?? false,
          );

      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${friendlyError(e)}\n(${widget.deviceIp})';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Enter your PIN',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connecting to ${widget.deviceIp}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            if (_loadingUsers)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: CircularProgressIndicator(),
              )
            else if (_userNames.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  _error ?? 'No users found on this device. Please set up the device first.',
                  style: TextStyle(color: AppColors.error, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_userNames.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedUser,
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'User',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CubieRadii.card),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CubieRadii.card),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                  items: _userNames
                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedUser = v),
                ),
              )
            else if (_userNames.length == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _selectedUser!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              obscureText: true,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              style: const TextStyle(
                fontSize: 32,
                letterSpacing: 16,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '0000',
                hintStyle: TextStyle(
                  fontSize: 32,
                  letterSpacing: 16,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CubieRadii.card),
                  borderSide: BorderSide(color: AppColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CubieRadii.card),
                  borderSide: BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CubieRadii.card),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CubieRadii.card),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Text(
                        'Connect',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.background,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
