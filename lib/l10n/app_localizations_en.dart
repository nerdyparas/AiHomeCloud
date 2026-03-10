// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'AiHomeCloud';

  @override
  String genericError(String error) {
    return 'Error: $error';
  }

  @override
  String get buttonCancel => 'Cancel';

  @override
  String get buttonAdd => 'Add';

  @override
  String get buttonRemove => 'Remove';

  @override
  String get buttonSave => 'Save';

  @override
  String get buttonChange => 'Change';

  @override
  String get buttonCreate => 'Create';

  @override
  String get buttonRetry => 'Retry';

  @override
  String dashboardGreeting(String userName) {
    return 'Hey, $userName 👋';
  }

  @override
  String get dashboardLoading => 'Loading…';

  @override
  String get dashboardDeviceError => 'Device error';

  @override
  String get dashboardSdCardWarning =>
      'No external storage active — files are on the SD card. Connect a USB drive or NVMe SSD for better performance.';

  @override
  String get dashboardStorageSection => 'Storage';

  @override
  String get dashboardManage => 'Manage';

  @override
  String dashboardMoreDevices(int count) {
    return '+$count more device(s)';
  }

  @override
  String get dashboardSystemSection => 'System';

  @override
  String get dashboardCpuLabel => 'CPU';

  @override
  String get dashboardMemoryLabel => 'Memory';

  @override
  String get dashboardTemperatureLabel => 'Temperature';

  @override
  String get dashboardUptimeLabel => 'Uptime';

  @override
  String get dashboardNetworkSection => 'Network';

  @override
  String get dashboardUpload => 'Upload';

  @override
  String get dashboardDownload => 'Download';

  @override
  String get dashboardNoExternalStorage => 'No external storage';

  @override
  String get dashboardTapToManageStorage => 'Tap to manage storage devices';

  @override
  String get storageStatusActive => 'Active';

  @override
  String get storageStatusMounted => 'Activated';

  @override
  String get storageStatusUnformatted => 'Unformatted';

  @override
  String get storageStatusReady => 'Ready';

  @override
  String get storageStatusSystem => 'System';

  @override
  String get familyTitle => 'Family';

  @override
  String get familySubtitle => 'Manage family members and their storage';

  @override
  String familyMemberFiles(String name) {
    return '$name\'s Files';
  }

  @override
  String get familyAddMemberTitle => 'Add Family Member';

  @override
  String get familyNameHint => 'Name';

  @override
  String familyRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get familyRemoveWarning =>
      'This will remove their account and all their files. This action cannot be undone.';

  @override
  String get familyAdminBadge => 'Admin';

  @override
  String familyStorageUsed(String size) {
    return '$size GB used';
  }

  @override
  String get myFilesTitle => 'My Files';

  @override
  String get sharedTitle => 'Shared';

  @override
  String get sharedNetworkAccess => 'Network Access';

  @override
  String get sharedNetworkInfo =>
      'TV & Computer Sharing  •  Smart TV Streaming';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsNetworkSection => 'Network';

  @override
  String get settingsWifiLabel => 'Wi-Fi';

  @override
  String get settingsWifiConnected => 'Connected';

  @override
  String get settingsWifiNotConnected => 'Not connected';

  @override
  String get settingsToggleOff => 'Off';

  @override
  String get settingsHotspotLabel => 'Hotspot';

  @override
  String get settingsHotspotActive => 'Active';

  @override
  String get settingsBluetoothLabel => 'Bluetooth';

  @override
  String get settingsBluetoothOn => 'On';

  @override
  String get settingsDeviceSection => 'Device';

  @override
  String get settingsDeviceName => 'Name';

  @override
  String get settingsDeviceSerial => 'Serial';

  @override
  String get settingsDeviceIp => 'IP Address';

  @override
  String get settingsDeviceFirmware => 'Firmware';

  @override
  String get settingsFirmwareUpdateSection => 'Firmware Update';

  @override
  String get settingsServicesSection => 'Services';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsChangePin => 'Change PIN';

  @override
  String get settingsLogout => 'Logout';

  @override
  String settingsAppVersion(String version) {
    return 'AiHomeCloud v$version';
  }

  @override
  String get settingsChecking => 'Checking…';

  @override
  String get settingsCheckForUpdates => 'Check for Updates';

  @override
  String settingsUpdateAvailable(String version) {
    return 'v$version available';
  }

  @override
  String settingsUpdateSize(String size) {
    return '$size MB';
  }

  @override
  String get settingsInstallUpdate => 'Install Update';

  @override
  String get settingsUpdateStarted =>
      'Update started. Device will reboot automatically.';

  @override
  String get settingsDeviceNameDialogTitle => 'Device Name';

  @override
  String get settingsDeviceNameHint => 'Enter device name';

  @override
  String get settingsChangePinDialogTitle => 'Change PIN';

  @override
  String get settingsCurrentPinHint => 'Current PIN';

  @override
  String get settingsNewPinHint => 'New PIN';

  @override
  String get settingsPinChangedSuccess => 'PIN changed successfully';

  @override
  String get settingsLogoutDialogTitle => 'Logout?';

  @override
  String get settingsLogoutWarning =>
      'You will need to pair your device again to use the app.';

  @override
  String get settingsEthernetLabel => 'Ethernet';

  @override
  String get settingsNoIp => 'No IP';

  @override
  String get settingsCableNotConnected => 'Cable not connected';

  @override
  String get settingsEthernetConnected => 'Connected';

  @override
  String get settingsEthernetDisconnected => 'Disconnected';

  @override
  String get settingsLanIpWarning =>
      'Changing the LAN IP may make this device unreachable.';

  @override
  String settingsNetworkError(String error) {
    return 'Network error: $error';
  }

  @override
  String get storageExplorerTitle => 'Storage';

  @override
  String get storageExplorerScanTooltip => 'Scan for devices';

  @override
  String get storageExplorerFailedToLoad => 'Failed to load devices';

  @override
  String get storageExplorerExternalSection => 'External Storage';

  @override
  String get storageExplorerSystemSection => 'System (OS)';

  @override
  String get storageExplorerNoDevices => 'No external storage detected';

  @override
  String get storageExplorerConnectPrompt =>
      'Connect a USB drive or storage device';

  @override
  String get storageExplorerScanning => 'Scanning…';

  @override
  String get storageExplorerScanAgain => 'Scan Again';

  @override
  String storageExplorerMounted(String name) {
    return '$name is ready to use';
  }

  @override
  String storageExplorerMountFailed(String error) {
    return 'Could not connect storage: $error';
  }

  @override
  String get storageExplorerUnmounted => 'Storage stopped and ready to remove';

  @override
  String storageExplorerUnmountFailed(String error) {
    return 'Could not stop using storage: $error';
  }

  @override
  String storageExplorerEjected(String name) {
    return '$name is safe to unplug';
  }

  @override
  String storageExplorerEjectFailed(String error) {
    return 'Could not remove storage safely: $error';
  }

  @override
  String get storageExplorerFormatTitle => 'Prepare Device';

  @override
  String storageExplorerFormatWarning(String name, String size) {
    return 'All files on $name ($size) will be permanently deleted.\nThis cannot be undone.';
  }

  @override
  String get storageExplorerVolumeLabel => 'Volume label';

  @override
  String get storageExplorerVolumeLabelHint => 'AiHomeNAS';

  @override
  String storageExplorerTypeToConfirm(String path) {
    return 'Type \"$path\" to confirm:';
  }

  @override
  String storageExplorerFormatted(String name) {
    return '$name prepared for use';
  }

  @override
  String storageExplorerFormatFailed(String error) {
    return 'Could not prepare device: $error';
  }

  @override
  String get storageExplorerFilesInUse => 'Files In Use';

  @override
  String storageExplorerBlockersMessage(int count) {
    return '$count app(s) are still using this storage:';
  }

  @override
  String get storageExplorerForceUnmount => 'Remove Anyway';

  @override
  String get storageActionUnmount => 'Stop using';

  @override
  String get storageActionSafeRemove => 'Remove safely';

  @override
  String get storageActionMount => 'Connect';

  @override
  String get storageActionFormat => 'Prepare device';

  @override
  String get storageActionEject => 'Remove safely';

  @override
  String get safeRemoveTitle => 'Remove safely';

  @override
  String safeRemoveDescription(String name) {
    return 'We will stop sharing, disconnect $name, and make it safe to unplug.\n\nMake sure all transfers are complete first.';
  }

  @override
  String get safeRemoveStepStopServices => 'Stop sharing';

  @override
  String get safeRemoveStepFlushWrites => 'Finish pending transfers';

  @override
  String get safeRemoveStepPowerOff => 'Make it safe to unplug';

  @override
  String get safeRemoveEjectNow => 'Remove safely';

  @override
  String get filePreviewDownloadTooltip => 'Download';

  @override
  String get filePreviewFailedToLoad => 'Failed to load file';

  @override
  String get filePreviewNoContent => 'No content';

  @override
  String get filePreviewVideoNotSupported =>
      'Video preview not supported yet.\nDownload the file to view it.';

  @override
  String get filePreviewAudioNotSupported =>
      'Audio preview not supported yet.\nDownload the file to play it.';

  @override
  String get filePreviewUnsupportedType =>
      'Preview not available for this file type.\nDownload the file to open it.';

  @override
  String filePreviewDownloadStarted(String fileName) {
    return 'Download started: $fileName';
  }

  @override
  String get filePreviewDownloadButton => 'Download';

  @override
  String get splashTagline => 'Your home, your cloud';

  @override
  String get welcomeTitle => 'Welcome to\nAiHomeCloud';

  @override
  String get welcomeSubtitle =>
      'Your personal home cloud. Store photos, videos, and files — all on your own device.\nNo subscriptions, no limits.';

  @override
  String get welcomeScanQr => 'Scan QR Code';

  @override
  String get qrScanTitle => 'Scan QR Code';

  @override
  String get qrScanInvalidCode =>
      'Invalid QR code. Scan the code on your AiHomeCloud box.';

  @override
  String get qrScanMissingData => 'QR code is missing required data.';

  @override
  String get qrScanReadError => 'Could not read QR code. Please try again.';

  @override
  String get qrScanInstructions =>
      'Point your camera at the QR code\non the bottom of your AiHomeCloud box';

  @override
  String get qrScanDemoButton => 'Use Demo QR (Testing)';

  @override
  String get discoverySearchingTitle => 'Finding Your AiHomeCloud';

  @override
  String get discoveryFoundTitle => 'Device Found!';

  @override
  String get discoveryFailedTitle => 'Connection Failed';

  @override
  String get discoveryRetry => 'Retry';

  @override
  String get discoveryScanAgain => 'Scan Again';

  @override
  String get setupDevicePaired => 'Device Paired!';

  @override
  String get setupProfilePrompt => 'Let\'s set up your profile';

  @override
  String get setupYourName => 'Your Name';

  @override
  String get setupNameHint => 'e.g. Dad, Mom, Alex…';

  @override
  String get setupNameRequired => 'Please enter your name';

  @override
  String get setupPinLabel => 'PIN (Optional)';

  @override
  String get setupPinHint => '4-digit PIN';

  @override
  String get setupPinTooShort => 'PIN must be at least 4 digits';

  @override
  String get setupPinHelperText =>
      'A PIN adds a layer of privacy for your personal folder.';

  @override
  String get setupGetStarted => 'Get Started';

  @override
  String get navHome => 'Home';

  @override
  String get navMyFiles => 'My Files';

  @override
  String get navFamily => 'Family';

  @override
  String get navShared => 'Shared';

  @override
  String get navSettings => 'Settings';

  @override
  String get fileActionRename => 'Rename';

  @override
  String get fileActionDelete => 'Delete';

  @override
  String get fileRenameHint => 'New name';

  @override
  String fileDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get fileDeleteFolderWarning =>
      'This folder and all its contents will be permanently deleted.';

  @override
  String get fileDeleteFileWarning => 'This file will be permanently deleted.';

  @override
  String get fileUploadTitle => 'Upload File';

  @override
  String get fileUploadSubtitle => 'Choose from your phone';

  @override
  String get fileNewFolderTitle => 'New Folder';

  @override
  String get fileNewFolderSubtitle => 'Create a new directory';

  @override
  String get fileNewFolderHint => 'Folder name';

  @override
  String fileUploadSuccess(String fileName) {
    return '$fileName uploaded successfully';
  }

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get folderEmptyHint =>
      'Upload files or create a folder to get started';
}
