import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';

/// Wi-Fi settings screen — Android-style network picker.
///
/// Hierarchy:
///   1. Connected network (single tap → edit password / disconnect / forget)
///   2. Saved networks (tap to reconnect, long-press or tap gear → modify/delete)
///   3. Available networks (tap → password dialog → connect)
class WifiSettingsScreen extends ConsumerStatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  ConsumerState<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends ConsumerState<WifiSettingsScreen> {
  List<WifiNetwork>? _networks;
  List<WifiNetwork>? _savedNetworks;
  bool _scanning = false;
  String? _error;
  String? _connectingSsid;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final results = await Future.wait([
        api.scanWifiNetworks(),
        api.getSavedWifiNetworks(),
      ]);
      if (mounted) {
        setState(() {
          _networks = results[0];
          _savedNetworks = results[1];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e));
        _showSnack(friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Connect flow ──────────────────────────────────────────────────────────

  Future<void> _onNetworkTap(WifiNetwork network) async {
    if (network.inUse) {
      // Single tap on connected network → show details with edit/disconnect
      await _showConnectedSheet(network);
      return;
    }

    if (network.saved) {
      // Tap saved network → show manage options (reconnect / edit password / forget)
      await _showSavedSheet(network);
      return;
    }

    if (network.isOpen) {
      await _connect(network.ssid, '');
      return;
    }

    // New secured network → password dialog
    _showPasswordDialog(network);
  }

  void _showPasswordDialog(WifiNetwork network, {bool isEdit = false}) {
    final ctrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: CubieColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                network.signal > 0
                    ? _signalIcon(network.signal)
                    : Icons.wifi_rounded,
                color: CubieColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(network.ssid,
                    style: GoogleFonts.sora(
                        color: CubieColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Enter new password',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(network.security,
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12)),
                ),
              TextField(
                controller: ctrl,
                autofocus: true,
                obscureText: obscure,
                style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded,
                      color: CubieColors.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: CubieColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (_) {
                  if (ctrl.text.isNotEmpty) {
                    Navigator.pop(ctx);
                    _connect(network.ssid, ctrl.text);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (ctrl.text.isNotEmpty) {
                  Navigator.pop(ctx);
                  _connect(network.ssid, ctrl.text);
                }
              },
              child: Text(isEdit ? 'Save & Connect' : 'Connect',
                  style:
                      GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(String ssid, String password) async {
    setState(() => _connectingSsid = ssid);
    try {
      final result =
          await ref.read(apiServiceProvider).connectWifi(ssid, password);
      if (result.success) {
        _showSnack(result.message);
        ref.invalidate(networkStatusProvider);
        await _loadAll();
      } else {
        _showSnack(result.message);
      }
    } catch (e) {
      _showSnack('Connection failed: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _connectingSsid = null);
    }
  }

  // ── Connected network sheet ───────────────────────────────────────────────

  Future<void> _showConnectedSheet(WifiNetwork network) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CubieColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.wifi_rounded,
                      color: CubieColors.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(network.ssid,
                        style: GoogleFonts.sora(
                            color: CubieColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CubieColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Connected',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('Security', network.security),
              _detailRow('Signal strength', '${network.signal}%'),
              const SizedBox(height: 20),

              // Action buttons: Edit Password / Disconnect / Forget
              _sheetAction(
                icon: Icons.edit_rounded,
                label: 'Edit password',
                color: CubieColors.primary,
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.link_off_rounded,
                label: 'Disconnect',
                color: CubieColors.textSecondary,
                onTap: () => Navigator.pop(ctx, 'disconnect'),
              ),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Forget network',
                color: CubieColors.error,
                onTap: () => Navigator.pop(ctx, 'forget'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        _showPasswordDialog(network, isEdit: true);
      case 'disconnect':
        await _disconnect();
      case 'forget':
        _confirmForget(network.ssid);
    }
  }

  // ── Saved network sheet ───────────────────────────────────────────────────

  Future<void> _showSavedSheet(WifiNetwork network) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CubieColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    network.signal > 0
                        ? _signalIcon(network.signal)
                        : Icons.wifi_rounded,
                    color: CubieColors.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(network.ssid,
                        style: GoogleFonts.sora(
                            color: CubieColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CubieColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Saved',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (network.security.isNotEmpty && network.security != 'Open')
                _detailRow('Security', network.security),
              if (network.signal > 0)
                _detailRow('Signal strength', '${network.signal}%'),
              const SizedBox(height: 20),

              // Action buttons
              if (network.signal > 0) ...[
                _sheetAction(
                  icon: Icons.wifi_rounded,
                  label: 'Connect',
                  color: CubieColors.success,
                  onTap: () => Navigator.pop(ctx, 'connect'),
                ),
                const SizedBox(height: 8),
              ],
              _sheetAction(
                icon: Icons.edit_rounded,
                label: 'Edit password',
                color: CubieColors.primary,
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Forget network',
                color: CubieColors.error,
                onTap: () => Navigator.pop(ctx, 'forget'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'connect':
        await _connect(network.ssid, '');
      case 'edit':
        _showPasswordDialog(network, isEdit: true);
      case 'forget':
        _confirmForget(network.ssid);
    }
  }

  // ── Sheet action button ───────────────────────────────────────────────────

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 14),
              Text(label,
                  style: GoogleFonts.dmSans(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 13)),
            Text(value,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );

  // ── Disconnect & Forget ───────────────────────────────────────────────────

  Future<void> _disconnect() async {
    setState(() => _scanning = true);
    try {
      await ref.read(apiServiceProvider).disconnectWifi();
      _showSnack('Disconnected');
      ref.invalidate(networkStatusProvider);
      await _loadAll();
    } catch (e) {
      _showSnack('Disconnect failed: ${friendlyError(e)}');
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _confirmForget(String ssid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CubieColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Forget $ssid?',
            style: GoogleFonts.sora(
                color: CubieColors.textPrimary, fontSize: 16)),
        content: Text(
            'This will remove the saved password. '
            'You\'ll need to enter it again to reconnect.',
            style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: CubieColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              _forget(ssid);
            },
            child: Text('Forget',
                style:
                    GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _forget(String ssid) async {
    setState(() => _scanning = true);
    try {
      await ref.read(apiServiceProvider).forgetWifiNetwork(ssid);
      _showSnack('Network forgotten');
      ref.invalidate(networkStatusProvider);
      await _loadAll();
    } catch (e) {
      _showSnack('Forget failed: ${friendlyError(e)}');
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ── Signal icons ──────────────────────────────────────────────────────────

  static IconData _signalIcon(int signal) {
    if (signal >= 75) return Icons.network_wifi_rounded;
    if (signal >= 50) return Icons.network_wifi_3_bar_rounded;
    if (signal >= 25) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  static Color _signalColor(int signal) {
    if (signal >= 60) return CubieColors.success;
    if (signal >= 35) return CubieColors.primary;
    return CubieColors.error;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        backgroundColor: CubieColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: CubieColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Wi-Fi',
            style: GoogleFonts.sora(
                color: CubieColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: CubieColors.primary),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: CubieColors.textSecondary),
              onPressed: _loadAll,
              tooltip: 'Rescan',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null && _networks == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: CubieColors.textMuted, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Retry',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    if (_networks == null) {
      return const Center(
        child: CircularProgressIndicator(color: CubieColors.primary),
      );
    }

    if (_networks!.isEmpty && (_savedNetworks == null || _savedNetworks!.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_find_rounded,
                color: CubieColors.textMuted, size: 48),
            const SizedBox(height: 16),
            Text('No networks found',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Scan again',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    // Build sections from scan results
    final connected = _networks!.where((n) => n.inUse).toList();
    final available = _networks!.where((n) => !n.inUse && !n.saved).toList();

    // Saved = merge scan-visible saved + backend saved-only (not in range)
    final scannedSavedSsids =
        _networks!.where((n) => !n.inUse && n.saved).map((n) => n.ssid).toSet();
    final savedFromScan =
        _networks!.where((n) => !n.inUse && n.saved).toList();
    final savedOnlyFromBackend = (_savedNetworks ?? [])
        .where((n) => !n.inUse && !scannedSavedSsids.contains(n.ssid))
        .toList();
    final allSaved = [...savedFromScan, ...savedOnlyFromBackend];

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: CubieColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Connected
          if (connected.isNotEmpty) ...[
            _sectionHeader('Connected'),
            ...connected.map((n) => _networkTile(n)),
            const SizedBox(height: 16),
          ],

          // 2. Saved networks
          if (allSaved.isNotEmpty) ...[
            _sectionHeader('Saved networks'),
            ...allSaved.map((n) => _networkTile(n)),
            const SizedBox(height: 16),
          ],

          // 3. Available networks
          if (available.isNotEmpty) ...[
            _sectionHeader('Available networks'),
            ...available.map((n) => _networkTile(n)),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text,
            style: GoogleFonts.sora(
                color: CubieColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );

  Widget _networkTile(WifiNetwork network) {
    final isConnecting = _connectingSsid == network.ssid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isConnecting ? null : () => _onNetworkTap(network),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: network.inUse
                  ? CubieColors.primary.withOpacity(0.08)
                  : CubieColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: network.inUse
                    ? CubieColors.primary.withOpacity(0.3)
                    : CubieColors.cardBorder,
              ),
            ),
            child: Row(
              children: [
                // Signal icon
                Icon(
                  network.signal > 0
                      ? _signalIcon(network.signal)
                      : Icons.wifi_rounded,
                  color: network.inUse
                      ? CubieColors.primary
                      : network.signal > 0
                          ? _signalColor(network.signal)
                          : CubieColors.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 14),
                // SSID + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(network.ssid,
                          style: GoogleFonts.dmSans(
                              color: CubieColors.textPrimary,
                              fontSize: 14,
                              fontWeight: network.inUse
                                  ? FontWeight.w600
                                  : FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        network.inUse
                            ? 'Connected'
                            : network.saved
                                ? network.signal > 0
                                    ? 'Saved \u2022 ${network.security}'
                                    : 'Saved \u2022 Not in range'
                                : network.security,
                        style: GoogleFonts.dmSans(
                            color: network.inUse
                                ? CubieColors.success
                                : CubieColors.textSecondary,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Status icons
                if (isConnecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: CubieColors.primary),
                  )
                else if (network.inUse)
                  const Icon(Icons.settings_rounded,
                      color: CubieColors.textMuted, size: 20)
                else if (network.saved)
                  const Icon(Icons.settings_rounded,
                      color: CubieColors.textMuted, size: 18)
                else if (!network.isOpen)
                  const Icon(Icons.lock_rounded,
                      color: CubieColors.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }
}
