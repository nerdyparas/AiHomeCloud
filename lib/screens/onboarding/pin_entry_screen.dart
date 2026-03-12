import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers/core_providers.dart';
import '../../services/api_service.dart';
import '../../widgets/user_avatar.dart';

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
  List<UserPickerEntry> _users = [];
  UserPickerEntry? _selectedUser;
  bool _showPin = false;
  bool _loggingIn = false;
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final api = ApiService.instance;
      final entries = await api.fetchUserEntries(widget.deviceIp);
      if (!mounted) return;
      setState(() {
        _users = entries;
        _selectedUser = null;
        _showPin = false;
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
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiService.instance.loginWithPin(
        widget.deviceIp,
        _selectedUser!.name,
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
        username: user['name'] as String? ?? _selectedUser!.name,
        isAdmin: user['isAdmin'] as bool? ?? false,
      );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _onUserTapped(UserPickerEntry user) async {
    if (_selectedUser?.name == user.name && _showPin) return;
    setState(() {
      _selectedUser = user;
      _pinController.clear();
      _error = null;
      _showPin = false;
    });
    if (user.hasPin) {
      setState(() => _showPin = true);
    } else {
      setState(() => _loggingIn = true);
      try {
        final result = await ApiService.instance.loginWithPin(
          widget.deviceIp,
          user.name,
          '',
        );
        final accessToken = result['accessToken'] as String;
        final refreshToken = result['refreshToken'] as String?;
        final userData = result['user'] as Map<String, dynamic>;
        await ref.read(authSessionProvider.notifier).login(
          host: widget.deviceIp,
          port: AppConstants.apiPort,
          token: accessToken,
          refreshToken: refreshToken,
          username: userData['name'] as String? ?? user.name,
          isAdmin: userData['isAdmin'] as bool? ?? false,
        );
        if (!mounted) return;
        context.go('/dashboard');
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = friendlyError(e);
          _loggingIn = false;
          _selectedUser = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loadingUsers
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 56),
              const SizedBox(height: 20),
              Text("Can't reach your AiHomeCloud",
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                )),
              const SizedBox(height: 8),
              Text(widget.deviceIp,
                style: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _fetchUsers,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/'),
                child: Text('Find a different device',
                  style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(child: Text('No users found.',
        style: GoogleFonts.dmSans(color: AppColors.textMuted)));
    }

    return Column(
      children: [
        const Spacer(),
        Text('Who\'s using\nAiHomeCloud?',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          )),
        const SizedBox(height: 40),
        // Avatar grid
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            for (int i = 0; i < _users.length; i++)
              _AvatarTile(
                user: _users[i],
                colorIndex: i,
                isSelected: _selectedUser?.name == _users[i].name,
                isLoggingIn: _loggingIn && _selectedUser?.name == _users[i].name,
                onTap: _loggingIn ? null : () => _onUserTapped(_users[i]),
              ),
            // Add User tile
            GestureDetector(
              onTap: () async {
                final added = await context.push<bool>(
                  '/profile-creation',
                  extra: {'ip': widget.deviceIp, 'isAddingUser': true},
                );
                if (added == true) _fetchUsers();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.cardBorder, width: 1.5),
                    ),
                    child: const Icon(Icons.add_rounded, color: AppColors.textMuted, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text('Add User',
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    )),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        // PIN entry — shown only after user is selected
        if (_selectedUser != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Text('Enter PIN for $_selectedUser',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: GoogleFonts.sora(
                      color: AppColors.textMuted,
                      fontSize: 24,
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                    style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13)),
                ],
                if (_pinController.text.isEmpty) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _submit,
                    child: Text('No PIN? Tap here to continue',
                      style: GoogleFonts.dmSans(
                        color: AppColors.primary,
                        fontSize: 13,
                      )),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                      : Text('Connect',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          )),
                  ),
                ),
              ],
            ),
          ),
        ],
        // PIN section — slides in only for users with a PIN
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: _showPin && _selectedUser != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PIN for ${_selectedUser!.name}',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 8,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: GoogleFonts.sora(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          letterSpacing: 8,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '••••',
                          hintStyle: GoogleFonts.sora(
                            color: AppColors.textMuted,
                            fontSize: 24,
                            letterSpacing: 8,
                          ),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Enter',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const Spacer(),
      ],
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final UserPickerEntry user;
  final int colorIndex;
  final bool isSelected;
  final bool isLoggingIn;
  final VoidCallback? onTap;

  const _AvatarTile({
    required this.user,
    required this.colorIndex,
    required this.isSelected,
    required this.isLoggingIn,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            name: user.name,
            iconEmoji: user.iconEmoji,
            colorIndex: colorIndex,
            size: 72,
            isSelected: isSelected,
            isLoading: isLoggingIn,
          ),
          const SizedBox(height: 8),
          Text(
            user.name,
            style: GoogleFonts.dmSans(
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
