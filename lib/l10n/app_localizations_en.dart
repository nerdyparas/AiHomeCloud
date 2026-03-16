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
  String get storageStatusUnformatted => 'Not ready yet';

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
      'Their personal folder will be removed from this device.';

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
  String get storageExplorerVolumeLabelHint => 'AiHomeCloud';

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

  @override
  String get navMore => 'More';

  @override
  String get shellReconnecting => 'Reconnecting…';

  @override
  String shellUploadingProgress(int done, int total) {
    return 'Uploading $done of $total file(s)…';
  }

  @override
  String shellUploadComplete(int done, int total) {
    return '$done of $total file(s) saved to AiHomeCloud';
  }

  @override
  String get shellNotReachable => 'AiHomeCloud is not reachable.';

  @override
  String get shellCheckWifi =>
      'Check your Wi-Fi and make sure the device is powered on.';

  @override
  String get shellReconnect => 'Reconnect';

  @override
  String get moreScreenTitle => 'More';

  @override
  String get moreSectionSharing => 'Sharing';

  @override
  String get moreSectionPrivacySecurity => 'Privacy & Security';

  @override
  String get moreSectionFamilyStorage => 'Family & Storage';

  @override
  String get moreServiceTvComputer => 'TV & Computer Sharing';

  @override
  String get moreServiceTvSubtitleActive => 'DLNA + SMB active';

  @override
  String get moreServiceTvSubtitleInactive => 'Stream to TVs and computers';

  @override
  String get moreServiceNotAvailable => 'Not available';

  @override
  String get moreTelegramBot => 'Telegram Bot';

  @override
  String get moreTelegramSubtitle => 'Send files from anywhere';

  @override
  String get moreCertTitle => 'Server Certificate';

  @override
  String get moreCertPinned => '· pinned';

  @override
  String get moreCertNotPinned => '· not pinned';

  @override
  String get moreFamilyMembers => 'Family Members';

  @override
  String get moreFamilyMembersSubtitle => 'Manage users and storage';

  @override
  String get moreStorageDrive => 'Storage Drive';

  @override
  String get moreStorageDriveSubtitle => 'Manage drives and storage';

  @override
  String get moreDeviceTitle => 'Device';

  @override
  String get moreDeviceSubtitle => 'Device info and name';

  @override
  String get moreAppVersion => 'AiHomeCloud v1.0.0';

  @override
  String get moreTagline => 'Your personal home cloud';

  @override
  String get moreLogOut => 'Log Out';

  @override
  String get moreRestart => 'Restart';

  @override
  String get moreShutDown => 'Shut Down';

  @override
  String fileSearchEmpty(String query) {
    return 'No files found for ‘$query’';
  }

  @override
  String get storageValidationLabelMaxLength =>
      'Label must be 16 characters or fewer';

  @override
  String get storageValidationLabelChars =>
      'Label may only contain letters, numbers, hyphens, and underscores';

  @override
  String get buttonClose => 'Close';

  @override
  String get buttonRetryAction => 'Retry';

  @override
  String get buttonUndo => 'Undo';

  @override
  String get moreProfileEditSubtitle => 'Edit name, icon and PIN';

  @override
  String get moreCertFingerprintLabel => 'Pinned fingerprint:';

  @override
  String get moreCertNotPinnedYet => 'Not pinned yet';

  @override
  String get moreCertFingerprintDescription =>
      'This fingerprint is pinned to your device and used to verify the connection.';

  @override
  String get moreProfileChangePinTitle => 'Change my PIN';

  @override
  String get moreRestartDialogTitle => 'Restart AiHomeCloud?';

  @override
  String get moreRestartDialogMessage =>
      'The device will restart and come back online in about a minute.';

  @override
  String get moreRestartButton => 'Restart';

  @override
  String get moreRestartStartedSnackbar => 'AiHomeCloud is restarting.';

  @override
  String moreRestartFailedSnackbar(String error) {
    return 'Restart failed: $error';
  }

  @override
  String get moreShutdownDialogTitle => 'Shut Down AiHomeCloud?';

  @override
  String get moreShutdownDialogMessage =>
      'This will stop all active services, cancel file transfers, and safely power off the device. You will need physical access to turn it back on.';

  @override
  String get moreShutdownButton => 'Shut Down';

  @override
  String get moreShutdownStartedSnackbar => 'Shutting down AiHomeCloud…';

  @override
  String get moreShutdownCompleteSnackbar => 'AiHomeCloud is powering off.';

  @override
  String get moreTrashEmptyButton => 'Empty';

  @override
  String get familyMakeAdminTitle => 'Make Admin';

  @override
  String get familyRemoveAdminTitle => 'Remove Admin';

  @override
  String familyMakeAdminDescription(String name) {
    return '$name will be able to manage storage, services, and family members.';
  }

  @override
  String familyRemoveAdminDescription(String name) {
    return '$name will lose admin privileges.';
  }

  @override
  String get filesFolderSubtitlePersonal => 'Your private files';

  @override
  String get filesFolderSubtitleFamily => 'Shared with everyone';

  @override
  String get filesFolderSubtitleEntertainment => 'Movies, series, music';

  @override
  String get filesFolderSubtitleTrash => 'Recently deleted files';

  @override
  String filesSearchNoResults(String query) {
    return 'No documents found for “$query”';
  }

  @override
  String get filesNoStorageTitle => 'No Storage Connected';

  @override
  String get filesNoStorageMessage =>
      'Connect a USB drive or NVMe to your Cubie to use shared storage.';

  @override
  String get filesCheckAgainButton => 'Check Again';

  @override
  String get telegramPendingRequestsLabel => 'PENDING REQUESTS';

  @override
  String get telegramDenyButton => 'Deny';

  @override
  String get telegramApproveButton => 'Approve';

  @override
  String get telegramBotTokenRequiredError => 'Bot Token is required.';

  @override
  String get telegramLargeFileModeRequiredError =>
      'API ID and API Hash are required for large file mode.';

  @override
  String get telegramConfiguredSnackbar => 'Telegram Bot configured!';

  @override
  String get telegramSetupStepsTitle => 'Setup in 3 steps';

  @override
  String get telegramSetupStep1 => 'Open Telegram and search @BotFather';

  @override
  String get telegramSetupStep2 =>
      'Send /newbot — follow the steps and copy the token';

  @override
  String get telegramSetupStep3 =>
      'Paste the token below and tap Save. Then open your bot and send /auth to link your account.';

  @override
  String get telegramTokenHintConfigured =>
      'Enter new token to replace existing';

  @override
  String get telegramTokenHintExample =>
      '1234567890:ABCdefGHIjklMNOpqrSTUvwxyz';

  @override
  String get telegramBotTokenLabel => 'Bot Token';

  @override
  String get telegramSaveActivateButton => 'Save & Activate';

  @override
  String get telegramNoAccountsLinked => 'No accounts linked yet';

  @override
  String telegramAccountsLinked(int count) {
    return '$count account(s) linked';
  }

  @override
  String get telegramOpenBotSendAuth => 'Open your bot and send /auth';

  @override
  String telegramFileLimitLabel(int sizeMb) {
    return 'File upload limit: $sizeMb MB';
  }

  @override
  String get telegramLargeFileModeActive =>
      'Large file mode active — up to 2 GB';

  @override
  String get telegramLargeFileModeInactive =>
      'Enable large file mode below to upload up to 2 GB';

  @override
  String get telegramLargeFileModeTitle => 'Large file mode (up to 2 GB)';

  @override
  String get telegramLargeFileModeSubtitle =>
      'Requires Telegram API credentials and the local server setup script to be run on your device.';

  @override
  String get telegramApiCredentialsHint =>
      'Get API ID and Hash at my.telegram.org → API development tools';

  @override
  String get telegramApiIdLabel => 'API ID';

  @override
  String get telegramApiHashLabel => 'API Hash';

  @override
  String get telegramScriptHint =>
      'Run scripts/setup-telegram-local-api.sh on your device before enabling this.';

  @override
  String get telegramBotActiveStatus => 'Bot is active and polling';

  @override
  String get telegramBotConfiguredStatus => 'Configured but not running';

  @override
  String get telegramBotNotConfiguredStatus => 'Not configured';

  @override
  String get storageEmptyBannerTitle => 'Connect a USB or hard drive';

  @override
  String get storageEmptyBannerMessage =>
      'Plug in a USB drive or NVMe to your AiHomeCloud';

  @override
  String get storagePrepareDialogTitle => 'Prepare this drive?';

  @override
  String get storagePreparingTitle => 'Preparing your storage drive…';

  @override
  String get storagePreparingMessage =>
      'This takes about 2 minutes. Please keep the app open.';

  @override
  String get storageSafelyRemoveButton => 'Safely Remove';

  @override
  String get storageCouldNotLoadDrives => 'Could not load drives';

  @override
  String get profileChangePinDialogTitle => 'Change PIN';

  @override
  String get profileAddPinDialogTitle => 'Add PIN';

  @override
  String get profileNewPinHint => 'New PIN (4–8 digits)';

  @override
  String get profileConfirmPinHint => 'Confirm new PIN';

  @override
  String get profilePinTooShortError => 'PIN must be at least 4 digits';

  @override
  String get profilePinMismatchError => 'PINs do not match';

  @override
  String get profileRemovePinDialogTitle => 'Remove PIN?';

  @override
  String get profileRemovePinDialogMessage =>
      'Anyone on this device will be able to access your profile without a PIN.';

  @override
  String get profileDeleteDialogTitle => 'Delete Profile?';

  @override
  String get profileDeleteDialogMessage =>
      'This will permanently delete your profile and all your personal files stored on this device.';

  @override
  String get folderViewNoStorageTitle => 'No Storage Connected';

  @override
  String get folderViewNoStorageMessage =>
      'Connect a USB drive or NVMe to your Cubie to use shared storage.';

  @override
  String get folderViewCheckAgainButton => 'Check Again';

  @override
  String get folderViewBackTooltip => 'Go back';

  @override
  String get moreTrashTitle => 'Trash';

  @override
  String get moreTrashEmpty => 'Empty';

  @override
  String moreTrashItemCount(int count, int sizeMB) {
    return '$count item(s) · $sizeMB MB';
  }

  @override
  String get moreEmptyTrashDialogTitle => 'Empty Trash?';

  @override
  String moreEmptyTrashDialogMessage(int count) {
    return 'This will permanently delete $count item(s). This cannot be undone.';
  }

  @override
  String get moreEmptyTrashButton => 'Empty Trash';

  @override
  String get moreTrashEmptiedSnackbar => 'Trash emptied.';

  @override
  String moreShutdownFailedSnackbar(String error) {
    return 'Shutdown failed: $error';
  }

  @override
  String get moreRestartingSnackbar => 'Restarting AiHomeCloud…';

  @override
  String get trashScreenTitle => 'Trash';

  @override
  String get trashEmptyState => 'Trash is empty';

  @override
  String get trashEmptyAllButton => 'Empty All';

  @override
  String get trashDeletePermanentlyTitle => 'Delete permanently?';

  @override
  String trashDeletePermanentlyMessage(String name) {
    return '$name will be permanently deleted. This cannot be undone.';
  }

  @override
  String trashRestoredSnackbar(String name) {
    return 'Restored: $name';
  }

  @override
  String get trashDeleteButton => 'Delete';

  @override
  String trashDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get storageActivatedSnackbar => 'Storage activated!';

  @override
  String storageReadySnackbar(String size) {
    return 'Storage is ready! $size available';
  }

  @override
  String get storageReadySimpleSnackbar => 'Storage is ready!';

  @override
  String get storageActivateFailedSnackbar =>
      'Could not activate drive. Check the USB connection and try again.';

  @override
  String storageStoppedSnackbar(String name) {
    return '$name stopped. Safe to remove.';
  }

  @override
  String storageSafeToUnplugSnackbar(String name) {
    return '$name is safe to unplug';
  }

  @override
  String storagePrepareDialogMessage(String name) {
    return 'This will erase all files on $name and set it up for AiHomeCloud. This cannot be undone.';
  }

  @override
  String get storagePrepareButton => 'Prepare';

  @override
  String get storageActiveStatusBadge => '✓ Active Storage';

  @override
  String get storageReadyStatusBadge => 'Ready';

  @override
  String get storageNotReadyStatusBadge => 'Not ready yet';

  @override
  String get storageActivateButton => 'Activate';

  @override
  String get storagePrepareAsStorageButton => 'Prepare as Storage';

  @override
  String get storagePreparingSubtitle =>
      'This takes about 2 minutes. Please keep the app open.';

  @override
  String get storageBlockerDialogTitle => 'Files In Use';

  @override
  String storageBlockerDialogMessage(int count) {
    return '$count app(s) are still using this storage:';
  }

  @override
  String get storageRemoveAnywayButton => 'Remove Anyway';

  @override
  String get storageSafeRemoveSheetTitle => 'Remove safely';

  @override
  String storageSafeRemoveSheetBody(String name) {
    return 'We will stop sharing, disconnect $name, and make it safe to unplug.\n\nMake sure all transfers are complete first.';
  }

  @override
  String get storageSafeRemoveStepStopSharing => 'Stop sharing';

  @override
  String get storageSafeRemoveStepFinishTransfers => 'Finish pending transfers';

  @override
  String get storageSafeRemoveStepSafeToUnplug => 'Make it safe to unplug';

  @override
  String get profileEditTitle => 'Edit Profile';

  @override
  String get profileDisplayNameLabel => 'Display Name';

  @override
  String get profileDisplayNameHint => 'Your name';

  @override
  String get profileIconLabel => 'Icon';

  @override
  String get profileSaveChangesButton => 'Save Changes';

  @override
  String get profileUpdatedSnackbar => 'Profile updated';

  @override
  String get profileNameEmptyError => 'Name cannot be empty.';

  @override
  String get profilePinLabel => 'PIN';

  @override
  String get profileChangePinTitle => 'Change PIN';

  @override
  String get profileAddPinTitle => 'Add PIN';

  @override
  String get profileCurrentPinHint => 'Current PIN';

  @override
  String get profilePinMinLengthError => 'PIN must be at least 4 digits';

  @override
  String get profilePinsDoNotMatchError => 'PINs do not match';

  @override
  String get profilePinUpdatedSnackbar => 'PIN updated';

  @override
  String get profilePinAddedSnackbar => 'PIN added';

  @override
  String get profileRemovePinTitle => 'Remove PIN?';

  @override
  String get profileRemovePinMessage =>
      'Anyone on this device will be able to access your profile without a PIN.';

  @override
  String get profileRemovePinButton => 'Remove PIN';

  @override
  String get profilePinRemovedSnackbar => 'PIN removed';

  @override
  String get profileChangePinSubtitle => 'Update your current PIN';

  @override
  String get profileAddPinSubtitle => 'Add a PIN to protect this profile';

  @override
  String get profileNoPin => 'No PIN needed to access this profile';

  @override
  String get profileAccountLabel => 'Account';

  @override
  String get profileSwitchProfileTitle => 'Switch Profile';

  @override
  String get profileSwitchProfileSubtitle => 'Go back to the profile picker';

  @override
  String get profileDeleteTitle => 'Delete Profile?';

  @override
  String get profileDeleteMessage =>
      'This will permanently delete your profile and all your personal files stored on this device.';

  @override
  String get profileDeleteWarning => 'This cannot be undone.';

  @override
  String get profileDeleteButton => 'Delete Profile';

  @override
  String get profileDeleteListTitle => 'Delete Profile';

  @override
  String get profileDeleteListSubtitle => 'Permanently remove this profile';

  @override
  String get folderRenameTitle => 'Rename';

  @override
  String get folderRenameHint => 'New name';

  @override
  String get folderRenameButton => 'Rename';

  @override
  String get folderDeleteTitle => 'Delete';

  @override
  String folderMovedToTrash(String name) {
    return '$name moved to Trash';
  }

  @override
  String folderDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get folderUploadFileTitle => 'Upload File';

  @override
  String get folderUploadFileSubtitle => 'Choose from your phone';

  @override
  String get folderNewFolderTitle => 'New Folder';

  @override
  String get folderNewFolderSubtitle => 'Create a new directory';

  @override
  String get folderNewFolderHint => 'Folder name';

  @override
  String get folderCreateButton => 'Create';

  @override
  String folderUploadedSnackbar(String name) {
    return '✅ $name uploaded';
  }

  @override
  String folderUploadFailed(String error) {
    return 'Upload failed: $error';
  }

  @override
  String folderSortedToPhotos(String name) {
    return '📸 $name sorted to Photos';
  }

  @override
  String folderSortedToVideos(String name) {
    return '🎬 $name sorted to Videos';
  }

  @override
  String folderSortedToDocuments(String name) {
    return '📄 $name sorted to Documents';
  }

  @override
  String get folderGoBackTooltip => 'Go back';

  @override
  String get folderAddTooltip => 'Add file or folder';

  @override
  String get folderEmptyTitle => 'This folder is empty';

  @override
  String get folderEmptySubtitle =>
      'Upload files or create a folder to get started';
}
