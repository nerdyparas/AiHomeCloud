import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'navigation/app_router.dart';
import 'providers.dart';

/// Trust self-signed TLS certificates from the Cubie backend.
class _CubieHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
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

  // Auto-reconnect: if a device was previously paired, the AuthSessionNotifier
  // will restore the session from SharedPreferences on init. If not, the
  // router guard sends the user to /welcome → /scan-network for first-time setup.

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
    _shareHandler.initialize();
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
