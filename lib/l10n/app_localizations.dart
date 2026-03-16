import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud'**
  String get appName;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String genericError(String error);

  /// No description provided for @buttonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get buttonCancel;

  /// No description provided for @buttonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get buttonAdd;

  /// No description provided for @buttonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get buttonRemove;

  /// No description provided for @buttonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get buttonSave;

  /// No description provided for @buttonChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get buttonChange;

  /// No description provided for @buttonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get buttonCreate;

  /// No description provided for @buttonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get buttonRetry;

  /// No description provided for @dashboardGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hey, {userName} 👋'**
  String dashboardGreeting(String userName);

  /// No description provided for @dashboardLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get dashboardLoading;

  /// No description provided for @dashboardDeviceError.
  ///
  /// In en, this message translates to:
  /// **'Device error'**
  String get dashboardDeviceError;

  /// No description provided for @dashboardSdCardWarning.
  ///
  /// In en, this message translates to:
  /// **'No external storage active — files are on the SD card. Connect a USB drive or NVMe SSD for better performance.'**
  String get dashboardSdCardWarning;

  /// No description provided for @dashboardStorageSection.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get dashboardStorageSection;

  /// No description provided for @dashboardManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get dashboardManage;

  /// No description provided for @dashboardMoreDevices.
  ///
  /// In en, this message translates to:
  /// **'+{count} more device(s)'**
  String dashboardMoreDevices(int count);

  /// No description provided for @dashboardSystemSection.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get dashboardSystemSection;

  /// No description provided for @dashboardCpuLabel.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get dashboardCpuLabel;

  /// No description provided for @dashboardMemoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get dashboardMemoryLabel;

  /// No description provided for @dashboardTemperatureLabel.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get dashboardTemperatureLabel;

  /// No description provided for @dashboardUptimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get dashboardUptimeLabel;

  /// No description provided for @dashboardNetworkSection.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get dashboardNetworkSection;

  /// No description provided for @dashboardUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get dashboardUpload;

  /// No description provided for @dashboardDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get dashboardDownload;

  /// No description provided for @dashboardNoExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'No external storage'**
  String get dashboardNoExternalStorage;

  /// No description provided for @dashboardTapToManageStorage.
  ///
  /// In en, this message translates to:
  /// **'Tap to manage storage devices'**
  String get dashboardTapToManageStorage;

  /// No description provided for @storageStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get storageStatusActive;

  /// No description provided for @storageStatusMounted.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get storageStatusMounted;

  /// No description provided for @storageStatusUnformatted.
  ///
  /// In en, this message translates to:
  /// **'Not ready yet'**
  String get storageStatusUnformatted;

  /// No description provided for @storageStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get storageStatusReady;

  /// No description provided for @storageStatusSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get storageStatusSystem;

  /// No description provided for @familyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyTitle;

  /// No description provided for @familySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage family members and their storage'**
  String get familySubtitle;

  /// No description provided for @familyMemberFiles.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s Files'**
  String familyMemberFiles(String name);

  /// No description provided for @familyAddMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Family Member'**
  String get familyAddMemberTitle;

  /// No description provided for @familyNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get familyNameHint;

  /// No description provided for @familyRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String familyRemoveTitle(String name);

  /// No description provided for @familyRemoveWarning.
  ///
  /// In en, this message translates to:
  /// **'Their personal folder will be removed from this device.'**
  String get familyRemoveWarning;

  /// No description provided for @familyAdminBadge.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get familyAdminBadge;

  /// No description provided for @familyStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'{size} GB used'**
  String familyStorageUsed(String size);

  /// No description provided for @myFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Files'**
  String get myFilesTitle;

  /// No description provided for @sharedTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get sharedTitle;

  /// No description provided for @sharedNetworkAccess.
  ///
  /// In en, this message translates to:
  /// **'Network Access'**
  String get sharedNetworkAccess;

  /// No description provided for @sharedNetworkInfo.
  ///
  /// In en, this message translates to:
  /// **'TV & Computer Sharing  •  Smart TV Streaming'**
  String get sharedNetworkInfo;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsNetworkSection.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetworkSection;

  /// No description provided for @settingsWifiLabel.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get settingsWifiLabel;

  /// No description provided for @settingsWifiConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsWifiConnected;

  /// No description provided for @settingsWifiNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get settingsWifiNotConnected;

  /// No description provided for @settingsToggleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsToggleOff;

  /// No description provided for @settingsHotspotLabel.
  ///
  /// In en, this message translates to:
  /// **'Hotspot'**
  String get settingsHotspotLabel;

  /// No description provided for @settingsHotspotActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsHotspotActive;

  /// No description provided for @settingsBluetoothLabel.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get settingsBluetoothLabel;

  /// No description provided for @settingsBluetoothOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsBluetoothOn;

  /// No description provided for @settingsDeviceSection.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get settingsDeviceSection;

  /// No description provided for @settingsDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsDeviceName;

  /// No description provided for @settingsDeviceSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial'**
  String get settingsDeviceSerial;

  /// No description provided for @settingsDeviceIp.
  ///
  /// In en, this message translates to:
  /// **'IP Address'**
  String get settingsDeviceIp;

  /// No description provided for @settingsDeviceFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get settingsDeviceFirmware;

  /// No description provided for @settingsFirmwareUpdateSection.
  ///
  /// In en, this message translates to:
  /// **'Firmware Update'**
  String get settingsFirmwareUpdateSection;

  /// No description provided for @settingsServicesSection.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get settingsServicesSection;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsChangePin;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get settingsLogout;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud v{version}'**
  String settingsAppVersion(String version);

  /// No description provided for @settingsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsChecking;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'v{version} available'**
  String settingsUpdateAvailable(String version);

  /// No description provided for @settingsUpdateSize.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String settingsUpdateSize(String size);

  /// No description provided for @settingsInstallUpdate.
  ///
  /// In en, this message translates to:
  /// **'Install Update'**
  String get settingsInstallUpdate;

  /// No description provided for @settingsUpdateStarted.
  ///
  /// In en, this message translates to:
  /// **'Update started. Device will reboot automatically.'**
  String get settingsUpdateStarted;

  /// No description provided for @settingsDeviceNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Name'**
  String get settingsDeviceNameDialogTitle;

  /// No description provided for @settingsDeviceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter device name'**
  String get settingsDeviceNameHint;

  /// No description provided for @settingsChangePinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsChangePinDialogTitle;

  /// No description provided for @settingsCurrentPinHint.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get settingsCurrentPinHint;

  /// No description provided for @settingsNewPinHint.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get settingsNewPinHint;

  /// No description provided for @settingsPinChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'PIN changed successfully'**
  String get settingsPinChangedSuccess;

  /// No description provided for @settingsLogoutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout?'**
  String get settingsLogoutDialogTitle;

  /// No description provided for @settingsLogoutWarning.
  ///
  /// In en, this message translates to:
  /// **'You will need to pair your device again to use the app.'**
  String get settingsLogoutWarning;

  /// No description provided for @settingsEthernetLabel.
  ///
  /// In en, this message translates to:
  /// **'Ethernet'**
  String get settingsEthernetLabel;

  /// No description provided for @settingsNoIp.
  ///
  /// In en, this message translates to:
  /// **'No IP'**
  String get settingsNoIp;

  /// No description provided for @settingsCableNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Cable not connected'**
  String get settingsCableNotConnected;

  /// No description provided for @settingsEthernetConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsEthernetConnected;

  /// No description provided for @settingsEthernetDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get settingsEthernetDisconnected;

  /// No description provided for @settingsLanIpWarning.
  ///
  /// In en, this message translates to:
  /// **'Changing the LAN IP may make this device unreachable.'**
  String get settingsLanIpWarning;

  /// No description provided for @settingsNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Network error: {error}'**
  String settingsNetworkError(String error);

  /// No description provided for @storageExplorerTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageExplorerTitle;

  /// No description provided for @storageExplorerScanTooltip.
  ///
  /// In en, this message translates to:
  /// **'Scan for devices'**
  String get storageExplorerScanTooltip;

  /// No description provided for @storageExplorerFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load devices'**
  String get storageExplorerFailedToLoad;

  /// No description provided for @storageExplorerExternalSection.
  ///
  /// In en, this message translates to:
  /// **'External Storage'**
  String get storageExplorerExternalSection;

  /// No description provided for @storageExplorerSystemSection.
  ///
  /// In en, this message translates to:
  /// **'System (OS)'**
  String get storageExplorerSystemSection;

  /// No description provided for @storageExplorerNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No external storage detected'**
  String get storageExplorerNoDevices;

  /// No description provided for @storageExplorerConnectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB drive or storage device'**
  String get storageExplorerConnectPrompt;

  /// No description provided for @storageExplorerScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get storageExplorerScanning;

  /// No description provided for @storageExplorerScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan Again'**
  String get storageExplorerScanAgain;

  /// No description provided for @storageExplorerMounted.
  ///
  /// In en, this message translates to:
  /// **'{name} is ready to use'**
  String storageExplorerMounted(String name);

  /// No description provided for @storageExplorerMountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect storage: {error}'**
  String storageExplorerMountFailed(String error);

  /// No description provided for @storageExplorerUnmounted.
  ///
  /// In en, this message translates to:
  /// **'Storage stopped and ready to remove'**
  String get storageExplorerUnmounted;

  /// No description provided for @storageExplorerUnmountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not stop using storage: {error}'**
  String storageExplorerUnmountFailed(String error);

  /// No description provided for @storageExplorerEjected.
  ///
  /// In en, this message translates to:
  /// **'{name} is safe to unplug'**
  String storageExplorerEjected(String name);

  /// No description provided for @storageExplorerEjectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove storage safely: {error}'**
  String storageExplorerEjectFailed(String error);

  /// No description provided for @storageExplorerFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare Device'**
  String get storageExplorerFormatTitle;

  /// No description provided for @storageExplorerFormatWarning.
  ///
  /// In en, this message translates to:
  /// **'All files on {name} ({size}) will be permanently deleted.\nThis cannot be undone.'**
  String storageExplorerFormatWarning(String name, String size);

  /// No description provided for @storageExplorerVolumeLabel.
  ///
  /// In en, this message translates to:
  /// **'Volume label'**
  String get storageExplorerVolumeLabel;

  /// No description provided for @storageExplorerVolumeLabelHint.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud'**
  String get storageExplorerVolumeLabelHint;

  /// No description provided for @storageExplorerTypeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type \"{path}\" to confirm:'**
  String storageExplorerTypeToConfirm(String path);

  /// No description provided for @storageExplorerFormatted.
  ///
  /// In en, this message translates to:
  /// **'{name} prepared for use'**
  String storageExplorerFormatted(String name);

  /// No description provided for @storageExplorerFormatFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare device: {error}'**
  String storageExplorerFormatFailed(String error);

  /// No description provided for @storageExplorerFilesInUse.
  ///
  /// In en, this message translates to:
  /// **'Files In Use'**
  String get storageExplorerFilesInUse;

  /// No description provided for @storageExplorerBlockersMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) are still using this storage:'**
  String storageExplorerBlockersMessage(int count);

  /// No description provided for @storageExplorerForceUnmount.
  ///
  /// In en, this message translates to:
  /// **'Remove Anyway'**
  String get storageExplorerForceUnmount;

  /// No description provided for @storageActionUnmount.
  ///
  /// In en, this message translates to:
  /// **'Stop using'**
  String get storageActionUnmount;

  /// No description provided for @storageActionSafeRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove safely'**
  String get storageActionSafeRemove;

  /// No description provided for @storageActionMount.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get storageActionMount;

  /// No description provided for @storageActionFormat.
  ///
  /// In en, this message translates to:
  /// **'Prepare device'**
  String get storageActionFormat;

  /// No description provided for @storageActionEject.
  ///
  /// In en, this message translates to:
  /// **'Remove safely'**
  String get storageActionEject;

  /// No description provided for @safeRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove safely'**
  String get safeRemoveTitle;

  /// No description provided for @safeRemoveDescription.
  ///
  /// In en, this message translates to:
  /// **'We will stop sharing, disconnect {name}, and make it safe to unplug.\n\nMake sure all transfers are complete first.'**
  String safeRemoveDescription(String name);

  /// No description provided for @safeRemoveStepStopServices.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get safeRemoveStepStopServices;

  /// No description provided for @safeRemoveStepFlushWrites.
  ///
  /// In en, this message translates to:
  /// **'Finish pending transfers'**
  String get safeRemoveStepFlushWrites;

  /// No description provided for @safeRemoveStepPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Make it safe to unplug'**
  String get safeRemoveStepPowerOff;

  /// No description provided for @safeRemoveEjectNow.
  ///
  /// In en, this message translates to:
  /// **'Remove safely'**
  String get safeRemoveEjectNow;

  /// No description provided for @filePreviewDownloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get filePreviewDownloadTooltip;

  /// No description provided for @filePreviewFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load file'**
  String get filePreviewFailedToLoad;

  /// No description provided for @filePreviewNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get filePreviewNoContent;

  /// No description provided for @filePreviewVideoNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Video preview not supported yet.\nDownload the file to view it.'**
  String get filePreviewVideoNotSupported;

  /// No description provided for @filePreviewAudioNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Audio preview not supported yet.\nDownload the file to play it.'**
  String get filePreviewAudioNotSupported;

  /// No description provided for @filePreviewUnsupportedType.
  ///
  /// In en, this message translates to:
  /// **'Preview not available for this file type.\nDownload the file to open it.'**
  String get filePreviewUnsupportedType;

  /// No description provided for @filePreviewDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Download started: {fileName}'**
  String filePreviewDownloadStarted(String fileName);

  /// No description provided for @filePreviewDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get filePreviewDownloadButton;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Your home, your cloud'**
  String get splashTagline;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to\nAiHomeCloud'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your personal home cloud. Store photos, videos, and files — all on your own device.\nNo subscriptions, no limits.'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get welcomeScanQr;

  /// No description provided for @qrScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get qrScanTitle;

  /// No description provided for @qrScanInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code. Scan the code on your AiHomeCloud box.'**
  String get qrScanInvalidCode;

  /// No description provided for @qrScanMissingData.
  ///
  /// In en, this message translates to:
  /// **'QR code is missing required data.'**
  String get qrScanMissingData;

  /// No description provided for @qrScanReadError.
  ///
  /// In en, this message translates to:
  /// **'Could not read QR code. Please try again.'**
  String get qrScanReadError;

  /// No description provided for @qrScanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the QR code\non the bottom of your AiHomeCloud box'**
  String get qrScanInstructions;

  /// No description provided for @qrScanDemoButton.
  ///
  /// In en, this message translates to:
  /// **'Use Demo QR (Testing)'**
  String get qrScanDemoButton;

  /// No description provided for @discoverySearchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Finding Your AiHomeCloud'**
  String get discoverySearchingTitle;

  /// No description provided for @discoveryFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Found!'**
  String get discoveryFoundTitle;

  /// No description provided for @discoveryFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get discoveryFailedTitle;

  /// No description provided for @discoveryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get discoveryRetry;

  /// No description provided for @discoveryScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan Again'**
  String get discoveryScanAgain;

  /// No description provided for @setupDevicePaired.
  ///
  /// In en, this message translates to:
  /// **'Device Paired!'**
  String get setupDevicePaired;

  /// No description provided for @setupProfilePrompt.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your profile'**
  String get setupProfilePrompt;

  /// No description provided for @setupYourName.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get setupYourName;

  /// No description provided for @setupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dad, Mom, Alex…'**
  String get setupNameHint;

  /// No description provided for @setupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get setupNameRequired;

  /// No description provided for @setupPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN (Optional)'**
  String get setupPinLabel;

  /// No description provided for @setupPinHint.
  ///
  /// In en, this message translates to:
  /// **'4-digit PIN'**
  String get setupPinHint;

  /// No description provided for @setupPinTooShort.
  ///
  /// In en, this message translates to:
  /// **'PIN must be at least 4 digits'**
  String get setupPinTooShort;

  /// No description provided for @setupPinHelperText.
  ///
  /// In en, this message translates to:
  /// **'A PIN adds a layer of privacy for your personal folder.'**
  String get setupPinHelperText;

  /// No description provided for @setupGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get setupGetStarted;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMyFiles.
  ///
  /// In en, this message translates to:
  /// **'My Files'**
  String get navMyFiles;

  /// No description provided for @navFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get navFamily;

  /// No description provided for @navShared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get navShared;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @fileActionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileActionRename;

  /// No description provided for @fileActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get fileActionDelete;

  /// No description provided for @fileRenameHint.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get fileRenameHint;

  /// No description provided for @fileDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String fileDeleteTitle(String name);

  /// No description provided for @fileDeleteFolderWarning.
  ///
  /// In en, this message translates to:
  /// **'This folder and all its contents will be permanently deleted.'**
  String get fileDeleteFolderWarning;

  /// No description provided for @fileDeleteFileWarning.
  ///
  /// In en, this message translates to:
  /// **'This file will be permanently deleted.'**
  String get fileDeleteFileWarning;

  /// No description provided for @fileUploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload File'**
  String get fileUploadTitle;

  /// No description provided for @fileUploadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose from your phone'**
  String get fileUploadSubtitle;

  /// No description provided for @fileNewFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get fileNewFolderTitle;

  /// No description provided for @fileNewFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new directory'**
  String get fileNewFolderSubtitle;

  /// No description provided for @fileNewFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get fileNewFolderHint;

  /// No description provided for @fileUploadSuccess.
  ///
  /// In en, this message translates to:
  /// **'{fileName} uploaded successfully'**
  String fileUploadSuccess(String fileName);

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get folderEmpty;

  /// No description provided for @folderEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Upload files or create a folder to get started'**
  String get folderEmptyHint;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @shellReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get shellReconnecting;

  /// No description provided for @shellUploadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Uploading {done} of {total} file(s)…'**
  String shellUploadingProgress(int done, int total);

  /// No description provided for @shellUploadComplete.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} file(s) saved to AiHomeCloud'**
  String shellUploadComplete(int done, int total);

  /// No description provided for @shellNotReachable.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud is not reachable.'**
  String get shellNotReachable;

  /// No description provided for @shellCheckWifi.
  ///
  /// In en, this message translates to:
  /// **'Check your Wi-Fi and make sure the device is powered on.'**
  String get shellCheckWifi;

  /// No description provided for @shellReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get shellReconnect;

  /// No description provided for @moreScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreScreenTitle;

  /// No description provided for @moreSectionSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get moreSectionSharing;

  /// No description provided for @moreSectionPrivacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get moreSectionPrivacySecurity;

  /// No description provided for @moreSectionFamilyStorage.
  ///
  /// In en, this message translates to:
  /// **'Family & Storage'**
  String get moreSectionFamilyStorage;

  /// No description provided for @moreServiceTvComputer.
  ///
  /// In en, this message translates to:
  /// **'TV & Computer Sharing'**
  String get moreServiceTvComputer;

  /// No description provided for @moreServiceTvSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'DLNA + SMB active'**
  String get moreServiceTvSubtitleActive;

  /// No description provided for @moreServiceTvSubtitleInactive.
  ///
  /// In en, this message translates to:
  /// **'Stream to TVs and computers'**
  String get moreServiceTvSubtitleInactive;

  /// No description provided for @moreServiceNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get moreServiceNotAvailable;

  /// No description provided for @moreTelegramBot.
  ///
  /// In en, this message translates to:
  /// **'Telegram Bot'**
  String get moreTelegramBot;

  /// No description provided for @moreTelegramSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send files from anywhere'**
  String get moreTelegramSubtitle;

  /// No description provided for @moreCertTitle.
  ///
  /// In en, this message translates to:
  /// **'Server Certificate'**
  String get moreCertTitle;

  /// No description provided for @moreCertPinned.
  ///
  /// In en, this message translates to:
  /// **'· pinned'**
  String get moreCertPinned;

  /// No description provided for @moreCertNotPinned.
  ///
  /// In en, this message translates to:
  /// **'· not pinned'**
  String get moreCertNotPinned;

  /// No description provided for @moreFamilyMembers.
  ///
  /// In en, this message translates to:
  /// **'Family Members'**
  String get moreFamilyMembers;

  /// No description provided for @moreFamilyMembersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage users and storage'**
  String get moreFamilyMembersSubtitle;

  /// No description provided for @moreStorageDrive.
  ///
  /// In en, this message translates to:
  /// **'Storage Drive'**
  String get moreStorageDrive;

  /// No description provided for @moreStorageDriveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage drives and storage'**
  String get moreStorageDriveSubtitle;

  /// No description provided for @moreDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get moreDeviceTitle;

  /// No description provided for @moreDeviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Device info and name'**
  String get moreDeviceSubtitle;

  /// No description provided for @moreAppVersion.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud v1.0.0'**
  String get moreAppVersion;

  /// No description provided for @moreTagline.
  ///
  /// In en, this message translates to:
  /// **'Your personal home cloud'**
  String get moreTagline;

  /// No description provided for @moreLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get moreLogOut;

  /// No description provided for @moreRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get moreRestart;

  /// No description provided for @moreShutDown.
  ///
  /// In en, this message translates to:
  /// **'Shut Down'**
  String get moreShutDown;

  /// No description provided for @fileSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files found for ‘{query}’'**
  String fileSearchEmpty(String query);

  /// No description provided for @storageValidationLabelMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Label must be 16 characters or fewer'**
  String get storageValidationLabelMaxLength;

  /// No description provided for @storageValidationLabelChars.
  ///
  /// In en, this message translates to:
  /// **'Label may only contain letters, numbers, hyphens, and underscores'**
  String get storageValidationLabelChars;

  /// No description provided for @buttonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get buttonClose;

  /// No description provided for @buttonRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get buttonRetryAction;

  /// No description provided for @buttonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get buttonUndo;

  /// No description provided for @moreProfileEditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit name, icon and PIN'**
  String get moreProfileEditSubtitle;

  /// No description provided for @moreCertFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Pinned fingerprint:'**
  String get moreCertFingerprintLabel;

  /// No description provided for @moreCertNotPinnedYet.
  ///
  /// In en, this message translates to:
  /// **'Not pinned yet'**
  String get moreCertNotPinnedYet;

  /// No description provided for @moreCertFingerprintDescription.
  ///
  /// In en, this message translates to:
  /// **'This fingerprint is pinned to your device and used to verify the connection.'**
  String get moreCertFingerprintDescription;

  /// No description provided for @moreProfileChangePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Change my PIN'**
  String get moreProfileChangePinTitle;

  /// No description provided for @moreRestartDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart AiHomeCloud?'**
  String get moreRestartDialogTitle;

  /// No description provided for @moreRestartDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'The device will restart and come back online in about a minute.'**
  String get moreRestartDialogMessage;

  /// No description provided for @moreRestartButton.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get moreRestartButton;

  /// No description provided for @moreRestartStartedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud is restarting.'**
  String get moreRestartStartedSnackbar;

  /// No description provided for @moreRestartFailedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Restart failed: {error}'**
  String moreRestartFailedSnackbar(String error);

  /// No description provided for @moreShutdownDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Shut Down AiHomeCloud?'**
  String get moreShutdownDialogTitle;

  /// No description provided for @moreShutdownDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will stop all active services, cancel file transfers, and safely power off the device. You will need physical access to turn it back on.'**
  String get moreShutdownDialogMessage;

  /// No description provided for @moreShutdownButton.
  ///
  /// In en, this message translates to:
  /// **'Shut Down'**
  String get moreShutdownButton;

  /// No description provided for @moreShutdownStartedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Shutting down AiHomeCloud…'**
  String get moreShutdownStartedSnackbar;

  /// No description provided for @moreShutdownCompleteSnackbar.
  ///
  /// In en, this message translates to:
  /// **'AiHomeCloud is powering off.'**
  String get moreShutdownCompleteSnackbar;

  /// No description provided for @moreTrashEmptyButton.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get moreTrashEmptyButton;

  /// No description provided for @familyMakeAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Make Admin'**
  String get familyMakeAdminTitle;

  /// No description provided for @familyRemoveAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Admin'**
  String get familyRemoveAdminTitle;

  /// No description provided for @familyMakeAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'{name} will be able to manage storage, services, and family members.'**
  String familyMakeAdminDescription(String name);

  /// No description provided for @familyRemoveAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'{name} will lose admin privileges.'**
  String familyRemoveAdminDescription(String name);

  /// No description provided for @filesFolderSubtitlePersonal.
  ///
  /// In en, this message translates to:
  /// **'Your private files'**
  String get filesFolderSubtitlePersonal;

  /// No description provided for @filesFolderSubtitleFamily.
  ///
  /// In en, this message translates to:
  /// **'Shared with everyone'**
  String get filesFolderSubtitleFamily;

  /// No description provided for @filesFolderSubtitleEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Movies, series, music'**
  String get filesFolderSubtitleEntertainment;

  /// No description provided for @filesFolderSubtitleTrash.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted files'**
  String get filesFolderSubtitleTrash;

  /// No description provided for @filesSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No documents found for “{query}”'**
  String filesSearchNoResults(String query);

  /// No description provided for @filesNoStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'No Storage Connected'**
  String get filesNoStorageTitle;

  /// No description provided for @filesNoStorageMessage.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB drive or NVMe to your Cubie to use shared storage.'**
  String get filesNoStorageMessage;

  /// No description provided for @filesCheckAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Check Again'**
  String get filesCheckAgainButton;

  /// No description provided for @telegramPendingRequestsLabel.
  ///
  /// In en, this message translates to:
  /// **'PENDING REQUESTS'**
  String get telegramPendingRequestsLabel;

  /// No description provided for @telegramDenyButton.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get telegramDenyButton;

  /// No description provided for @telegramApproveButton.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get telegramApproveButton;

  /// No description provided for @telegramBotTokenRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Bot Token is required.'**
  String get telegramBotTokenRequiredError;

  /// No description provided for @telegramLargeFileModeRequiredError.
  ///
  /// In en, this message translates to:
  /// **'API ID and API Hash are required for large file mode.'**
  String get telegramLargeFileModeRequiredError;

  /// No description provided for @telegramConfiguredSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Telegram Bot configured!'**
  String get telegramConfiguredSnackbar;

  /// No description provided for @telegramSetupStepsTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup in 3 steps'**
  String get telegramSetupStepsTitle;

  /// No description provided for @telegramSetupStep1.
  ///
  /// In en, this message translates to:
  /// **'Open Telegram and search @BotFather'**
  String get telegramSetupStep1;

  /// No description provided for @telegramSetupStep2.
  ///
  /// In en, this message translates to:
  /// **'Send /newbot — follow the steps and copy the token'**
  String get telegramSetupStep2;

  /// No description provided for @telegramSetupStep3.
  ///
  /// In en, this message translates to:
  /// **'Paste the token below and tap Save. Then open your bot and send /auth to link your account.'**
  String get telegramSetupStep3;

  /// No description provided for @telegramTokenHintConfigured.
  ///
  /// In en, this message translates to:
  /// **'Enter new token to replace existing'**
  String get telegramTokenHintConfigured;

  /// No description provided for @telegramTokenHintExample.
  ///
  /// In en, this message translates to:
  /// **'1234567890:ABCdefGHIjklMNOpqrSTUvwxyz'**
  String get telegramTokenHintExample;

  /// No description provided for @telegramBotTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Bot Token'**
  String get telegramBotTokenLabel;

  /// No description provided for @telegramSaveActivateButton.
  ///
  /// In en, this message translates to:
  /// **'Save & Activate'**
  String get telegramSaveActivateButton;

  /// No description provided for @telegramNoAccountsLinked.
  ///
  /// In en, this message translates to:
  /// **'No accounts linked yet'**
  String get telegramNoAccountsLinked;

  /// No description provided for @telegramAccountsLinked.
  ///
  /// In en, this message translates to:
  /// **'{count} account(s) linked'**
  String telegramAccountsLinked(int count);

  /// No description provided for @telegramOpenBotSendAuth.
  ///
  /// In en, this message translates to:
  /// **'Open your bot and send /auth'**
  String get telegramOpenBotSendAuth;

  /// No description provided for @telegramFileLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'File upload limit: {sizeMb} MB'**
  String telegramFileLimitLabel(int sizeMb);

  /// No description provided for @telegramLargeFileModeActive.
  ///
  /// In en, this message translates to:
  /// **'Large file mode active — up to 2 GB'**
  String get telegramLargeFileModeActive;

  /// No description provided for @telegramLargeFileModeInactive.
  ///
  /// In en, this message translates to:
  /// **'Enable large file mode below to upload up to 2 GB'**
  String get telegramLargeFileModeInactive;

  /// No description provided for @telegramLargeFileModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Large file mode (up to 2 GB)'**
  String get telegramLargeFileModeTitle;

  /// No description provided for @telegramLargeFileModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Requires Telegram API credentials and the local server setup script to be run on your device.'**
  String get telegramLargeFileModeSubtitle;

  /// No description provided for @telegramApiCredentialsHint.
  ///
  /// In en, this message translates to:
  /// **'Get API ID and Hash at my.telegram.org → API development tools'**
  String get telegramApiCredentialsHint;

  /// No description provided for @telegramApiIdLabel.
  ///
  /// In en, this message translates to:
  /// **'API ID'**
  String get telegramApiIdLabel;

  /// No description provided for @telegramApiHashLabel.
  ///
  /// In en, this message translates to:
  /// **'API Hash'**
  String get telegramApiHashLabel;

  /// No description provided for @telegramScriptHint.
  ///
  /// In en, this message translates to:
  /// **'Run scripts/setup-telegram-local-api.sh on your device before enabling this.'**
  String get telegramScriptHint;

  /// No description provided for @telegramBotActiveStatus.
  ///
  /// In en, this message translates to:
  /// **'Bot is active and polling'**
  String get telegramBotActiveStatus;

  /// No description provided for @telegramBotConfiguredStatus.
  ///
  /// In en, this message translates to:
  /// **'Configured but not running'**
  String get telegramBotConfiguredStatus;

  /// No description provided for @telegramBotNotConfiguredStatus.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get telegramBotNotConfiguredStatus;

  /// No description provided for @storageEmptyBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB or hard drive'**
  String get storageEmptyBannerTitle;

  /// No description provided for @storageEmptyBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Plug in a USB drive or NVMe to your AiHomeCloud'**
  String get storageEmptyBannerMessage;

  /// No description provided for @storagePrepareDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare this drive?'**
  String get storagePrepareDialogTitle;

  /// No description provided for @storagePreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing your storage drive…'**
  String get storagePreparingTitle;

  /// No description provided for @storagePreparingMessage.
  ///
  /// In en, this message translates to:
  /// **'This takes about 2 minutes. Please keep the app open.'**
  String get storagePreparingMessage;

  /// No description provided for @storageSafelyRemoveButton.
  ///
  /// In en, this message translates to:
  /// **'Safely Remove'**
  String get storageSafelyRemoveButton;

  /// No description provided for @storageCouldNotLoadDrives.
  ///
  /// In en, this message translates to:
  /// **'Could not load drives'**
  String get storageCouldNotLoadDrives;

  /// No description provided for @profileChangePinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get profileChangePinDialogTitle;

  /// No description provided for @profileAddPinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add PIN'**
  String get profileAddPinDialogTitle;

  /// No description provided for @profileNewPinHint.
  ///
  /// In en, this message translates to:
  /// **'New PIN (4–8 digits)'**
  String get profileNewPinHint;

  /// No description provided for @profileConfirmPinHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm new PIN'**
  String get profileConfirmPinHint;

  /// No description provided for @profilePinTooShortError.
  ///
  /// In en, this message translates to:
  /// **'PIN must be at least 4 digits'**
  String get profilePinTooShortError;

  /// No description provided for @profilePinMismatchError.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get profilePinMismatchError;

  /// No description provided for @profileRemovePinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN?'**
  String get profileRemovePinDialogTitle;

  /// No description provided for @profileRemovePinDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Anyone on this device will be able to access your profile without a PIN.'**
  String get profileRemovePinDialogMessage;

  /// No description provided for @profileDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Profile?'**
  String get profileDeleteDialogTitle;

  /// No description provided for @profileDeleteDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your profile and all your personal files stored on this device.'**
  String get profileDeleteDialogMessage;

  /// No description provided for @folderViewNoStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'No Storage Connected'**
  String get folderViewNoStorageTitle;

  /// No description provided for @folderViewNoStorageMessage.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB drive or NVMe to your Cubie to use shared storage.'**
  String get folderViewNoStorageMessage;

  /// No description provided for @folderViewCheckAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Check Again'**
  String get folderViewCheckAgainButton;

  /// No description provided for @folderViewBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get folderViewBackTooltip;

  /// No description provided for @moreTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get moreTrashTitle;

  /// No description provided for @moreTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get moreTrashEmpty;

  /// No description provided for @moreTrashItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) · {sizeMB} MB'**
  String moreTrashItemCount(int count, int sizeMB);

  /// No description provided for @moreEmptyTrashDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get moreEmptyTrashDialogTitle;

  /// No description provided for @moreEmptyTrashDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete {count} item(s). This cannot be undone.'**
  String moreEmptyTrashDialogMessage(int count);

  /// No description provided for @moreEmptyTrashButton.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get moreEmptyTrashButton;

  /// No description provided for @moreTrashEmptiedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied.'**
  String get moreTrashEmptiedSnackbar;

  /// No description provided for @moreShutdownFailedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Shutdown failed: {error}'**
  String moreShutdownFailedSnackbar(String error);

  /// No description provided for @moreRestartingSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Restarting AiHomeCloud…'**
  String get moreRestartingSnackbar;

  /// No description provided for @trashScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashScreenTitle;

  /// No description provided for @trashEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmptyState;

  /// No description provided for @trashEmptyAllButton.
  ///
  /// In en, this message translates to:
  /// **'Empty All'**
  String get trashEmptyAllButton;

  /// No description provided for @trashDeletePermanentlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get trashDeletePermanentlyTitle;

  /// No description provided for @trashDeletePermanentlyMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} will be permanently deleted. This cannot be undone.'**
  String trashDeletePermanentlyMessage(String name);

  /// No description provided for @trashRestoredSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Restored: {name}'**
  String trashRestoredSnackbar(String name);

  /// No description provided for @trashDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get trashDeleteButton;

  /// No description provided for @trashDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String trashDaysAgo(int days);

  /// No description provided for @storageActivatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Storage activated!'**
  String get storageActivatedSnackbar;

  /// No description provided for @storageReadySnackbar.
  ///
  /// In en, this message translates to:
  /// **'Storage is ready! {size} available'**
  String storageReadySnackbar(String size);

  /// No description provided for @storageReadySimpleSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Storage is ready!'**
  String get storageReadySimpleSnackbar;

  /// No description provided for @storageActivateFailedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Could not activate drive. Check the USB connection and try again.'**
  String get storageActivateFailedSnackbar;

  /// No description provided for @storageStoppedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} stopped. Safe to remove.'**
  String storageStoppedSnackbar(String name);

  /// No description provided for @storageSafeToUnplugSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} is safe to unplug'**
  String storageSafeToUnplugSnackbar(String name);

  /// No description provided for @storagePrepareDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will erase all files on {name} and set it up for AiHomeCloud. This cannot be undone.'**
  String storagePrepareDialogMessage(String name);

  /// No description provided for @storagePrepareButton.
  ///
  /// In en, this message translates to:
  /// **'Prepare'**
  String get storagePrepareButton;

  /// No description provided for @storageActiveStatusBadge.
  ///
  /// In en, this message translates to:
  /// **'✓ Active Storage'**
  String get storageActiveStatusBadge;

  /// No description provided for @storageReadyStatusBadge.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get storageReadyStatusBadge;

  /// No description provided for @storageNotReadyStatusBadge.
  ///
  /// In en, this message translates to:
  /// **'Not ready yet'**
  String get storageNotReadyStatusBadge;

  /// No description provided for @storageActivateButton.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get storageActivateButton;

  /// No description provided for @storagePrepareAsStorageButton.
  ///
  /// In en, this message translates to:
  /// **'Prepare as Storage'**
  String get storagePrepareAsStorageButton;

  /// No description provided for @storagePreparingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This takes about 2 minutes. Please keep the app open.'**
  String get storagePreparingSubtitle;

  /// No description provided for @storageBlockerDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Files In Use'**
  String get storageBlockerDialogTitle;

  /// No description provided for @storageBlockerDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) are still using this storage:'**
  String storageBlockerDialogMessage(int count);

  /// No description provided for @storageRemoveAnywayButton.
  ///
  /// In en, this message translates to:
  /// **'Remove Anyway'**
  String get storageRemoveAnywayButton;

  /// No description provided for @storageSafeRemoveSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove safely'**
  String get storageSafeRemoveSheetTitle;

  /// No description provided for @storageSafeRemoveSheetBody.
  ///
  /// In en, this message translates to:
  /// **'We will stop sharing, disconnect {name}, and make it safe to unplug.\n\nMake sure all transfers are complete first.'**
  String storageSafeRemoveSheetBody(String name);

  /// No description provided for @storageSafeRemoveStepStopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get storageSafeRemoveStepStopSharing;

  /// No description provided for @storageSafeRemoveStepFinishTransfers.
  ///
  /// In en, this message translates to:
  /// **'Finish pending transfers'**
  String get storageSafeRemoveStepFinishTransfers;

  /// No description provided for @storageSafeRemoveStepSafeToUnplug.
  ///
  /// In en, this message translates to:
  /// **'Make it safe to unplug'**
  String get storageSafeRemoveStepSafeToUnplug;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditTitle;

  /// No description provided for @profileDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get profileDisplayNameLabel;

  /// No description provided for @profileDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get profileDisplayNameHint;

  /// No description provided for @profileIconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get profileIconLabel;

  /// No description provided for @profileSaveChangesButton.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get profileSaveChangesButton;

  /// No description provided for @profileUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdatedSnackbar;

  /// No description provided for @profileNameEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty.'**
  String get profileNameEmptyError;

  /// No description provided for @profilePinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get profilePinLabel;

  /// No description provided for @profileChangePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get profileChangePinTitle;

  /// No description provided for @profileAddPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Add PIN'**
  String get profileAddPinTitle;

  /// No description provided for @profileCurrentPinHint.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get profileCurrentPinHint;

  /// No description provided for @profilePinMinLengthError.
  ///
  /// In en, this message translates to:
  /// **'PIN must be at least 4 digits'**
  String get profilePinMinLengthError;

  /// No description provided for @profilePinsDoNotMatchError.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get profilePinsDoNotMatchError;

  /// No description provided for @profilePinUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'PIN updated'**
  String get profilePinUpdatedSnackbar;

  /// No description provided for @profilePinAddedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'PIN added'**
  String get profilePinAddedSnackbar;

  /// No description provided for @profileRemovePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN?'**
  String get profileRemovePinTitle;

  /// No description provided for @profileRemovePinMessage.
  ///
  /// In en, this message translates to:
  /// **'Anyone on this device will be able to access your profile without a PIN.'**
  String get profileRemovePinMessage;

  /// No description provided for @profileRemovePinButton.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get profileRemovePinButton;

  /// No description provided for @profilePinRemovedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'PIN removed'**
  String get profilePinRemovedSnackbar;

  /// No description provided for @profileChangePinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your current PIN'**
  String get profileChangePinSubtitle;

  /// No description provided for @profileAddPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a PIN to protect this profile'**
  String get profileAddPinSubtitle;

  /// No description provided for @profileNoPin.
  ///
  /// In en, this message translates to:
  /// **'No PIN needed to access this profile'**
  String get profileNoPin;

  /// No description provided for @profileAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccountLabel;

  /// No description provided for @profileSwitchProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch Profile'**
  String get profileSwitchProfileTitle;

  /// No description provided for @profileSwitchProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Go back to the profile picker'**
  String get profileSwitchProfileSubtitle;

  /// No description provided for @profileDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Profile?'**
  String get profileDeleteTitle;

  /// No description provided for @profileDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your profile and all your personal files stored on this device.'**
  String get profileDeleteMessage;

  /// No description provided for @profileDeleteWarning.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get profileDeleteWarning;

  /// No description provided for @profileDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete Profile'**
  String get profileDeleteButton;

  /// No description provided for @profileDeleteListTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Profile'**
  String get profileDeleteListTitle;

  /// No description provided for @profileDeleteListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently remove this profile'**
  String get profileDeleteListSubtitle;

  /// No description provided for @folderRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get folderRenameTitle;

  /// No description provided for @folderRenameHint.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get folderRenameHint;

  /// No description provided for @folderRenameButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get folderRenameButton;

  /// No description provided for @folderDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get folderDeleteTitle;

  /// No description provided for @folderMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{name} moved to Trash'**
  String folderMovedToTrash(String name);

  /// No description provided for @folderDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String folderDeleteFailed(String error);

  /// No description provided for @folderUploadFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload File'**
  String get folderUploadFileTitle;

  /// No description provided for @folderUploadFileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose from your phone'**
  String get folderUploadFileSubtitle;

  /// No description provided for @folderNewFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get folderNewFolderTitle;

  /// No description provided for @folderNewFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new directory'**
  String get folderNewFolderSubtitle;

  /// No description provided for @folderNewFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderNewFolderHint;

  /// No description provided for @folderCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get folderCreateButton;

  /// No description provided for @folderUploadedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'✅ {name} uploaded'**
  String folderUploadedSnackbar(String name);

  /// No description provided for @folderUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String folderUploadFailed(String error);

  /// No description provided for @folderSortedToPhotos.
  ///
  /// In en, this message translates to:
  /// **'📸 {name} sorted to Photos'**
  String folderSortedToPhotos(String name);

  /// No description provided for @folderSortedToVideos.
  ///
  /// In en, this message translates to:
  /// **'🎬 {name} sorted to Videos'**
  String folderSortedToVideos(String name);

  /// No description provided for @folderSortedToDocuments.
  ///
  /// In en, this message translates to:
  /// **'📄 {name} sorted to Documents'**
  String folderSortedToDocuments(String name);

  /// No description provided for @folderGoBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get folderGoBackTooltip;

  /// No description provided for @folderAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add file or folder'**
  String get folderAddTooltip;

  /// No description provided for @folderEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get folderEmptyTitle;

  /// No description provided for @folderEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload files or create a folder to get started'**
  String get folderEmptySubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
