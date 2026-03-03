/// App-wide constants for CubieCloud.
class CubieConstants {
  CubieConstants._();

  // ── API ────────────────────────────────────────────────────────────────────
  static const int apiPort = 8443;
  static const String apiScheme = 'https';
  static const String apiVersion = '/api/v1';

  // ── BLE ────────────────────────────────────────────────────────────────────
  static const String bleServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String bleCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String bleDevicePrefix = 'CubieCloud-';

  // ── mDNS ───────────────────────────────────────────────────────────────────
  static const String mdnsType = '_cubie-nas._tcp';
  static const Duration mdnsTimeout = Duration(seconds: 10);

  // ── QR ─────────────────────────────────────────────────────────────────────
  static const String qrScheme = 'cubie';
  static const String qrHost = 'pair';

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const String prefDeviceIp = 'device_ip';
  static const String prefDeviceToken = 'device_token';
  static const String prefDeviceName = 'device_name';
  static const String prefDeviceSerial = 'device_serial';
  static const String prefUserName = 'user_name';
  static const String prefUserPin = 'user_pin';
  static const String prefIsSetupDone = 'is_setup_done';
  static const String prefAuthToken = 'auth_token';

  // ── Storage ────────────────────────────────────────────────────────────────
  static const double totalStorageGB = 500.0;

  // ── Upload ─────────────────────────────────────────────────────────────────
  static const int uploadChunkSize = 1024 * 1024; // 1 MB

  // ── NAS paths ──────────────────────────────────────────────────────────────
  static const String personalBasePath = '/srv/nas/personal/';
  static const String sharedPath = '/srv/nas/shared/';
}
