import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'navigation/app_router.dart';
import 'providers.dart';
import 'services/api_service.dart';

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
    systemNavigationBarColor: CubieColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await SharedPreferences.getInstance();

  // ── DEV SHORTCUT: Skip onboarding, connect directly to Cubie ──────────
  // Remove this block once onboarding/QR flow is fully tested.
  const devMode = true;
  if (devMode && !prefs.containsKey(CubieConstants.prefIsSetupDone)) {
    const cubieIp = '192.168.0.212';
    ApiService.instance.configure(host: cubieIp);
    // Pair to get a real JWT
    try {
      debugPrint('[DEV] Pairing with Cubie at $cubieIp:${CubieConstants.apiPort}…');
      final token = await ApiService.instance
          .pairDevice('CUBIE-A7A-2025-001', 'your-pairing-key');
      debugPrint('[DEV] ✅ Paired! Token: ${token.substring(0, 20)}…');
      await prefs.setString(CubieConstants.prefDeviceIp, cubieIp);
      await prefs.setString(CubieConstants.prefAuthToken, token);
      await prefs.setString(CubieConstants.prefUserName, 'paras');
      await prefs.setString(
          CubieConstants.prefDeviceSerial, 'CUBIE-A7A-2025-001');
      await prefs.setString(CubieConstants.prefDeviceName, 'My CubieCloud');
      await prefs.setBool(CubieConstants.prefIsSetupDone, true);
    } catch (e) {
      debugPrint('[DEV] ❌ Pairing failed: $e');
      // If Cubie isn't reachable, fall through to normal onboarding
    }
  }
  // ── END DEV SHORTCUT ──────────────────────────────────────────────────

  // Configure the real API service with saved host/token if available
  final savedHost = prefs.getString(CubieConstants.prefDeviceIp);
  final savedToken = prefs.getString(CubieConstants.prefAuthToken);
  if (savedHost != null) {
    ApiService.instance.configure(host: savedHost, token: savedToken);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CubieCloudApp(),
    ),
  );
}

class CubieCloudApp extends ConsumerWidget {
  const CubieCloudApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'CubieCloud',
      debugShowCheckedModeBanner: false,
      theme: CubieTheme.dark,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
