import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Persistent bottom navigation bar shell used by the main app routes.
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _indexOf(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/dashboard')) return 0;
    if (loc.startsWith('/my-folder')) return 1;
    if (loc.startsWith('/family')) return 2;
    if (loc.startsWith('/shared')) return 3;
    if (loc.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _indexOf(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: CubieColors.cardBorder, width: 1),
          ),
        ),
        child: NavigationBar(
          backgroundColor: CubieColors.surface,
          indicatorColor: CubieColors.primary.withValues(alpha: 0.12),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 68,
          selectedIndex: idx,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go('/dashboard');
              case 1:
                context.go('/my-folder');
              case 2:
                context.go('/family');
              case 3:
                context.go('/shared');
              case 4:
                context.go('/settings');
            }
          },
          destinations: [
            _dest(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home',
                idx == 0),
            _dest(Icons.folder_outlined, Icons.folder_rounded, 'My Files',
                idx == 1),
            _dest(Icons.people_outline_rounded, Icons.people_rounded, 'Family',
                idx == 2),
            _dest(Icons.folder_shared_outlined, Icons.folder_shared_rounded,
                'Shared', idx == 3),
            _dest(Icons.settings_outlined, Icons.settings_rounded, 'Settings',
                idx == 4),
          ],
        ),
      ),
    );
  }

  NavigationDestination _dest(
      IconData icon, IconData activeIcon, String label, bool active) {
    return NavigationDestination(
      icon: Icon(icon,
          color: active ? CubieColors.primary : CubieColors.textMuted,
          size: 22),
      selectedIcon: Icon(activeIcon, color: CubieColors.primary, size: 22),
      label: label,
    );
  }
}
