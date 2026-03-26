import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'core/tls_config.dart';
import 'l10n/app_localizations.dart';
import 'navigation/app_router.dart';
import 'providers/core_providers.dart';
import 'services/backup_worker.dart';
import 'services/share_handler.dart';

/// Trust self-signed TLS certificates from the Cubie backend only.
///
/// Scoped to the known device IP + API port. During onboarding (before
/// any session is saved) [trustedDeviceHost] is null and only the port is
/// checked — needed so health-check probes during discovery can succeed.
/// Once a session exists the host must also match.
class _CubieHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) {
        if (port != AppConstants.apiPort) return false;
        final trusted = trustedDeviceHost;
        return trusted == null || host == trusted;
      };
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Trust self-signed certs globally (for Image.network, etc.)
  HttpOverrides.global = _CubieHttpOverrides();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Dark status / nav bars to match the theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await SharedPreferences.getInstance();

  // Scope TLS bypass to the previously paired device IP (if any).
  // null during first-time onboarding — port-only check applies until login.
  trustedDeviceHost = prefs.getString(AppConstants.prefDeviceIp);

  // Initialise WorkManager for background auto-backup tasks.
  await BackupWorker.instance.initialize();
  await BackupWorker.instance.schedulePeriodicBackup();

  // Auto-reconnect: if a device was previously paired, the AuthSessionNotifier
  // will restore the session from SharedPreferences on init. If not, the
  // router guard sends the user through the onboarding flow for first-time setup.

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AiHomeCloudApp(),
    ),
  );
}

class AiHomeCloudApp extends ConsumerStatefulWidget {
  const AiHomeCloudApp({super.key});

  @override
  ConsumerState<AiHomeCloudApp> createState() => _AiHomeCloudAppState();
}

class _AiHomeCloudAppState extends ConsumerState<AiHomeCloudApp> {
  late final ShareHandler _shareHandler;

  @override
  void initState() {
    super.initState();
    _shareHandler = ShareHandler(
      progress: ref.read(shareUploadProvider.notifier),
      getSession: () => ref.read(authSessionProvider),
    );
    try {
      _shareHandler.initialize();
    } catch (_) {
      // Share handler init can fail on some devices; non-critical.
    }
  }

  @override
  void dispose() {
    _shareHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AiHomeCloud',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
