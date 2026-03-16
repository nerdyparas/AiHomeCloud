import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

class _PinEntryScreenState extends ConsumerState<PinEntryScreen>
    with SingleTickerProviderStateMixin {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<UserPickerEntry> _users = [];
  UserPickerEntry? _selectedUser;
  bool _showPin = false;
  bool _loggingIn = false;
  bool _loadingUsers = true;
  late final AnimationController _bgController;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final cacheKey = AppConstants.prefUserPickerCachePrefix + widget.deviceIp;

    // Load persisted cache immediately — no spinner if cached data exists
    final raw = prefs.getString(cacheKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final cached = list
            .map((m) => UserPickerEntry(
                  name: m['name'] as String,
                  hasPin: m['hasPin'] as bool,
                  iconEmoji: m['iconEmoji'] as String? ?? '',
                ))
            .toList();
        if (cached.isNotEmpty) {
          setState(() {
            _users = cached;
            _loadingUsers = false;
            _error = null;
          });
        }
      } catch (_) {
        // Corrupted cache — ignore, spinner stays until fresh fetch arrives
      }
    }

    // Always refresh from server in background
    try {
      final api = ApiService.instance;
      final entries = await api.fetchUserEntries(widget.deviceIp);
      // Persist updated list to survive process death
      await prefs.setString(
        cacheKey,
        jsonEncode(entries
            .map((e) => {
                  'name': e.name,
                  'hasPin': e.hasPin,
                  'iconEmoji': e.iconEmoji,
                })
            .toList()),
      );
      if (!mounted) return;
      // Debounce: delay the background setState by 300 ms to avoid clobbering
      // the UI while the user is actively typing their PIN.
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _users = entries;
          _loadingUsers = false;
          // Preserve current selection if user still exists in the refreshed list
          if (_selectedUser != null) {
            final stillExists = entries.any((u) => u.name == _selectedUser!.name);
            if (!stillExists) {
              _selectedUser = null;
              _pinController.clear();
              _showPin = false;
            }
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        // Only surface error when there is nothing cached to show
        if (_users.isEmpty) _error = friendlyError(e);
      });
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _bgController.dispose();
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
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
          _selectedUser = null;
        });
      } finally {
        if (mounted) setState(() => _loggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          final t = _bgController.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFF0B0B0F), const Color(0xFF12122A), t)!,
                  Color.lerp(const Color(0xFF0F0F1E), const Color(0xFF1A1A3A), t)!,
                  Color.lerp(const Color(0xFF12122A), const Color(0xFF0B0B0F), t)!,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: child!,
          );
        },
        child: SafeArea(
          child: _loadingUsers
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _buildBody(),
        ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Welcome to\nAiHomeCloud",
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No profiles yet. Set up yours to get started.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push<bool>(
                    '/profile-creation',
                    extra: {'ip': widget.deviceIp, 'isAddingUser': false},
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Create your profile',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Who's using\nAiHomeCloud?",
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 56),
            Wrap(
              spacing: 40,
              runSpacing: 32,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < _users.length; i++)
                  _ProfileAvatarTile(
                    user: _users[i],
                    colorIndex: i,
                    isSelected: _selectedUser?.name == _users[i].name,
                    isLoggingIn: _loggingIn && _selectedUser?.name == _users[i].name,
                    onTap: _loggingIn ? null : () => _onUserTapped(_users[i]),
                  )
                      .animate()
                      .fadeIn(
                        delay: Duration(milliseconds: i * 80),
                        duration: const Duration(milliseconds: 300),
                      )
                      .slideY(
                        begin: 0.12,
                        end: 0,
                        delay: Duration(milliseconds: i * 80),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                _AddUserTile(
                  onTap: () async {
                    final added = await context.push<bool>(
                      '/profile-creation',
                      extra: {'ip': widget.deviceIp, 'isAddingUser': true},
                    );
                    if (added == true) _fetchUsers();
                  },
                )
                    .animate()
                    .fadeIn(
                      delay: Duration(milliseconds: _users.length * 80),
                      duration: const Duration(milliseconds: 300),
                    )
                    .slideY(
                      begin: 0.12,
                      end: 0,
                      delay: Duration(milliseconds: _users.length * 80),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    ),
              ],
            ),
            // PIN entry — slides in for users with a PIN
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: _showPin && _selectedUser != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(0, 40, 0, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'PIN for ${_selectedUser!.name}',
                            style: GoogleFonts.dmSans(
                              color: const Color(0xFFB0B0C0),
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
                              color: Colors.white,
                              fontSize: 24,
                              letterSpacing: 8,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '••••',
                              hintStyle: GoogleFonts.sora(
                                color: const Color(0xFF505065),
                                fontSize: 24,
                                letterSpacing: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF1A1A2E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFF3A3A5A)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFF3A3A5A)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 2),
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.error, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
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
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// ── Profile avatar tile ───────────────────────────────────────────────────────

class _ProfileAvatarTile extends StatefulWidget {
  final UserPickerEntry user;
  final int colorIndex;
  final bool isSelected;
  final bool isLoggingIn;
  final VoidCallback? onTap;

  const _ProfileAvatarTile({
    required this.user,
    required this.colorIndex,
    required this.isSelected,
    required this.isLoggingIn,
    this.onTap,
  });

  @override
  State<_ProfileAvatarTile> createState() => _ProfileAvatarTileState();
}

class _ProfileAvatarTileState extends State<_ProfileAvatarTile> {
  double _scale = 1.0;

  static const _gradients = [
    [Color(0xFFE8A84C), Color(0xFFE86C4C)],
    [Color(0xFF4C9BE8), Color(0xFF6C4CE8)],
    [Color(0xFF4CE88A), Color(0xFF4CE8D8)],
    [Color(0xFFE84CA8), Color(0xFF9B50E8)],
    [Color(0xFF9B59B6), Color(0xFF6C3483)],
    [Color(0xFF1ABC9C), Color(0xFF0E8C7A)],
    [Color(0xFFE74C3C), Color(0xFFC0392B)],
    [Color(0xFF3498DB), Color(0xFF2176AE)],
  ];

  List<Color> get _gradient =>
      _gradients[widget.colorIndex % _gradients.length].cast<Color>();

  Color get _accentColor => _gradient[0];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 1.08),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: widget.isSelected
                    ? Border.all(color: Colors.white, width: 3)
                    : Border.all(
                        color: _accentColor.withValues(alpha: 0.0),
                        width: 3,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withValues(
                        alpha: widget.isSelected ? 0.55 : 0.25),
                    blurRadius: widget.isSelected ? 24 : 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: widget.isLoggingIn
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : widget.user.iconEmoji.isNotEmpty
                        ? Text(
                            widget.user.iconEmoji,
                            style: const TextStyle(fontSize: 40),
                          )
                        : Text(
                            widget.user.name.isNotEmpty
                                ? widget.user.name[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.sora(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.user.name,
              style: GoogleFonts.dmSans(
                color: widget.isSelected
                    ? Colors.white
                    : const Color(0xFFB0B0C0),
                fontSize: 14,
                fontWeight:
                    widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add user tile ─────────────────────────────────────────────────────────────

class _AddUserTile extends StatefulWidget {
  final VoidCallback? onTap;
  const _AddUserTile({this.onTap});

  @override
  State<_AddUserTile> createState() => _AddUserTileState();
}

class _AddUserTileState extends State<_AddUserTile> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 1.08),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E1E2E),
                border: Border.all(
                  color: const Color(0xFF3A3A5A),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Color(0xFF8080A0),
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add User',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF8080A0),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
