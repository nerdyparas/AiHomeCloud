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
  /// **'Unformatted'**
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
  /// **'This will remove their account and all their files. This action cannot be undone.'**
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
  /// **'Storage Devices'**
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
  /// **'Connect a USB drive or NVMe SSD'**
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
  /// **'{name} activated as NAS storage'**
  String storageExplorerMounted(String name);

  /// No description provided for @storageExplorerMountFailed.
  ///
  /// In en, this message translates to:
  /// **'Activate failed: {error}'**
  String storageExplorerMountFailed(String error);

  /// No description provided for @storageExplorerUnmounted.
  ///
  /// In en, this message translates to:
  /// **'Storage safely removed'**
  String get storageExplorerUnmounted;

  /// No description provided for @storageExplorerUnmountFailed.
  ///
  /// In en, this message translates to:
  /// **'Remove failed: {error}'**
  String storageExplorerUnmountFailed(String error);

  /// No description provided for @storageExplorerEjected.
  ///
  /// In en, this message translates to:
  /// **'{name} safely ejected — you can remove it'**
  String storageExplorerEjected(String name);

  /// No description provided for @storageExplorerEjectFailed.
  ///
  /// In en, this message translates to:
  /// **'Eject failed: {error}'**
  String storageExplorerEjectFailed(String error);

  /// No description provided for @storageExplorerFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Format Device'**
  String get storageExplorerFormatTitle;

  /// No description provided for @storageExplorerFormatWarning.
  ///
  /// In en, this message translates to:
  /// **'This will ERASE ALL DATA on {name} ({size}).\nThis cannot be undone.'**
  String storageExplorerFormatWarning(String name, String size);

  /// No description provided for @storageExplorerVolumeLabel.
  ///
  /// In en, this message translates to:
  /// **'Volume label'**
  String get storageExplorerVolumeLabel;

  /// No description provided for @storageExplorerVolumeLabelHint.
  ///
  /// In en, this message translates to:
  /// **'CubieNAS'**
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
  /// **'Format failed: {error}'**
  String storageExplorerFormatFailed(String error);

  /// No description provided for @storageExplorerFilesInUse.
  ///
  /// In en, this message translates to:
  /// **'Files In Use'**
  String get storageExplorerFilesInUse;

  /// No description provided for @storageExplorerBlockersMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} process(es) have open files on the NAS:'**
  String storageExplorerBlockersMessage(int count);

  /// No description provided for @storageExplorerForceUnmount.
  ///
  /// In en, this message translates to:
  /// **'Force Remove'**
  String get storageExplorerForceUnmount;

  /// No description provided for @storageActionUnmount.
  ///
  /// In en, this message translates to:
  /// **'Safely Remove'**
  String get storageActionUnmount;

  /// No description provided for @storageActionSafeRemove.
  ///
  /// In en, this message translates to:
  /// **'Safe Remove'**
  String get storageActionSafeRemove;

  /// No description provided for @storageActionMount.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get storageActionMount;

  /// No description provided for @storageActionFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get storageActionFormat;

  /// No description provided for @storageActionEject.
  ///
  /// In en, this message translates to:
  /// **'Eject'**
  String get storageActionEject;

  /// No description provided for @safeRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Safe Remove'**
  String get safeRemoveTitle;

  /// No description provided for @safeRemoveDescription.
  ///
  /// In en, this message translates to:
  /// **'This will stop NAS services, unmount {name}, and power off the USB port.\n\nMake sure all transfers are complete.'**
  String safeRemoveDescription(String name);

  /// No description provided for @safeRemoveStepStopServices.
  ///
  /// In en, this message translates to:
  /// **'Stop file sharing services'**
  String get safeRemoveStepStopServices;

  /// No description provided for @safeRemoveStepFlushWrites.
  ///
  /// In en, this message translates to:
  /// **'Flush writes & unmount'**
  String get safeRemoveStepFlushWrites;

  /// No description provided for @safeRemoveStepPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Power off USB port'**
  String get safeRemoveStepPowerOff;

  /// No description provided for @safeRemoveEjectNow.
  ///
  /// In en, this message translates to:
  /// **'Eject Now'**
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
