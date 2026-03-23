Run flutter test --exclude-tags golden

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:8)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:9)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/network_scanner_test.dart: DiscoveredHost defaults isAhc to false

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:10)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/network_scanner_test.dart: DiscoveredHost stores all fields when provided

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:11)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/network_scanner_test.dart: NetworkScanner instance is a singleton

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:12)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: FileListResponse deserialization parses items and totalCount from well-formed JSON

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:13)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: FileListResponse deserialization totalCount falls back to item count when absent

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:14)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: FileListResponse deserialization page and pageSize are stored on the response

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:15)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: StorageStats model parses totalGB and usedGB from numeric JSON

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:16)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: StorageStats model usedPercent clamps to 1.0 when over-full

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:17)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: StorageDevice.fromJson deserialization parses all fields including displayName and bestPartition

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:18)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: StorageDevice.fromJson deserialization handles null optional fields gracefully

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:19)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: JobStatus.fromJson deserialization parses running job correctly

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:20)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: JobStatus.fromJson deserialization isTerminal is true for completed status

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:21)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/api_service_test.dart: JobStatus.fromJson deserialization isTerminal is true for failed status

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:22)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” login login() sets all session fields on the state

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:23)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” login login() persists host, port, username to SharedPreferences

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:24)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” logout logout() clears all session state fields to null

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:25)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” logout logout() removes token keys from SharedPreferences

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:26)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” updateToken updateToken() replaces token without touching other fields

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:27)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: AuthSessionNotifier â€” updateToken updateToken() is a no-op when not logged in

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:28)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: ConnectionNotifier â€” grace period state does NOT change to disconnected within 9 seconds of failure

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:29)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: ConnectionNotifier â€” grace period state transitions to disconnected after 10-second grace period

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:30)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/services/auth_session_test.dart: ConnectionNotifier â€” grace period markConnected() cancels debounce and resets to connected

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:31)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders with required label and value

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:32)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders icon badge with correct styling

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:33)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders unit text when provided

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:34)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders helper text when provided

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:35)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders Card container with border and rounded corners

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:36)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) uses vertical column layout

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:37)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) applies custom accent color to icon badge

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:38)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/stat_tile_test.dart: StatTile Widget Tests (TASK-025) renders correctly with all optional parameters

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:39)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: shows initial letter when no emoji provided

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:40)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: shows emoji when iconEmoji is set

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:41)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: shows ? for empty name with no emoji

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:42)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: shows loading spinner when isLoading is true

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:43)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: renders at custom size

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:44)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: applies selection border when isSelected

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:45)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/user_avatar_test.dart: cycles through color palette by colorIndex

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:46)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests renders at 0% fill without throwing

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:47)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests renders at 50% fill without throwing

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:48)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests renders at 100% fill without throwing

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:49)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests handles over-filled storage gracefully

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:50)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests handles zero total storage

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:51)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/storage_donut_chart_test.dart: StorageDonutChart Widget Tests renders at custom size

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:52)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/folder_view_test.dart: renders without crashing

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:53)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/folder_view_test.dart: shows loading indicator initially (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:79)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/folder_view_test.dart: handles read-only mode property

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:80)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests tap callback fires when tile is tapped

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:81)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests long-press callback fires when tile is long-pressed

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:82)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests displays file icon for files

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:83)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests displays folder icon for directories

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:84)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests displays file name

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:85)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests displays context menu icon

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:86)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/file_list_tile_test.dart: FileListTile Widget Tests multiple taps and long-presses work correctly

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:87)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: renders two section labels

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:88)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: renders 32 emoji tiles

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:89)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: fires onSelected when emoji is tapped

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:90)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: shows "Use a different emoji" link

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:91)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: tapping link shows custom input field

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:92)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/emoji_picker_grid_test.dart: highlights currently selected emoji

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:93)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/notification_listener_test.dart: renders child widget

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:94)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/notification_listener_test.dart: wraps child in Stack for overlay positioning

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:95)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/notification_listener_test.dart: shows toast when notification arrives

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:96)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/notification_listener_test.dart: toast auto-dismisses after 4 seconds

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:97)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/widgets/notification_listener_test.dart: does not crash with no notifications

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:98)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/dashboard_screen_test.dart: shows CircularProgressIndicator while device info is loading (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:129)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/dashboard_screen_test.dart: shows error text when device info fails

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:130)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/dashboard_screen_test.dart: renders dashboard content when data is available

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:131)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/device_settings_screen_test.dart: shows loading indicator while device info loads (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:157)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/device_settings_screen_test.dart: shows error text when device info fails

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:158)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/device_settings_screen_test.dart: renders device information when data is available

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:159)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen renders Files title at the top (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:298)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen displays three primary folder cards in root view (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:437)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen folder cards have descriptive subtitles (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:576)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen displays Trash folder card (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:715)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen root view shows ListView with horizontal padding (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:854)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/files_screen_test.dart: FilesScreen tapping folder card does not crash (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:999)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/file_preview_screen_test.dart: renders video file preview without crashing (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1138)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/file_preview_screen_test.dart: renders image file preview without crashing (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1272)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/file_preview_screen_test.dart: renders audio file preview without crashing (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1406)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/file_preview_screen_test.dart: shows filename in AppBar title (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1540)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/splash_screen_test.dart: renders splash screen without crashing (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1576)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/splash_screen_test.dart: shows app name (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1612)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/pin_entry_screen_test.dart: PinEntryScreen shows loading indicator while fetching users (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1643)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/pin_entry_screen_test.dart: PinEntryScreen displays question text when users are loaded

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1644)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/pin_entry_screen_test.dart: PinEntryScreen shows error message when user fetch fails

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1645)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/pin_entry_screen_test.dart: PinEntryScreen has a Retry button when in error state

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1646)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_creation_screen_test.dart: ProfileCreationScreen renders emoji picker and name input

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1647)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_creation_screen_test.dart: ProfileCreationScreen shows error when name is empty and submit is tapped

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1648)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_creation_screen_test.dart: ProfileCreationScreen emoji avatar renders when emoji is selected

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1649)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_creation_screen_test.dart: ProfileCreationScreen name input field accepts text

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1650)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/family_screen_test.dart: shows loading indicator while family data loads (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1676)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/family_screen_test.dart: shows error text when family users fail to load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1677)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/family_screen_test.dart: renders family member cards when data is available

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1678)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/family_screen_test.dart: does not crash with empty member list

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1679)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/telegram_setup_screen_test.dart: renders without crashing (error state on no server)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1680)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/telegram_setup_screen_test.dart: shows loading indicator initially (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1706)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/telegram_setup_screen_test.dart: contains AppBar

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1707)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/storage_explorer_screen_test.dart: renders without crashing (error state on no server)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1708)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/storage_explorer_screen_test.dart: contains AppBar with back button (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1734)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen renders More title at the top (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1917)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_edit_screen_test.dart: renders without crashing when no session

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:1918)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen has safe area with padding (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2096)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen renders ListView to display sections (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2274)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen contains Sharing section label (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2452)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_edit_screen_test.dart: pre-populates name from auth session

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2453)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen displays TV & Computer Sharing card (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2631)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen contains ListTiles for grouped items (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2809)✅ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/profile_edit_screen_test.dart: contains emoji picker

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2810)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen shows profile area with user name (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:2983)❌ /home/runner/work/AiHomeCloud/AiHomeCloud/test/screens/more_screen_test.dart: MoreScreen screen does not crash when built (failed)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:3156)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:3157)Error: 83 tests passed, 27 failed.

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157378/job/67274839745#step:7:3158)Error: Process completed with exit code 1.
