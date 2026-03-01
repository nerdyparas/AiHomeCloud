import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'navigation/app_router.dart';
import 'providers.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    );
  }
}
