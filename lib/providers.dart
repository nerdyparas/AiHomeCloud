/// Barrel file â€” re-exports all provider domain files.
///
/// Import this single file to access every provider in the app:
///   import 'package:aihomecloud/providers.dart';
library;
export 'providers/core_providers.dart';
export 'providers/device_providers.dart';
export 'providers/file_providers.dart';
export 'providers/data_providers.dart';
export 'providers/discovery_providers.dart';

// Re-export so screens get ApiService extensions via `import providers.dart`.
export 'services/api_service.dart';
export 'services/share_handler.dart';

