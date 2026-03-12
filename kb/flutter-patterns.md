# Flutter Patterns — AiHomeCloud

> Descriptions of patterns actually used in the codebase, not prescriptions.
> Verified against source code as of 2025-07-25.

---

## Widget Composition

**AppCard as container:** Most card-style UI sections wrap content in `AppCard`, which provides consistent padding, border radius (`CubieRadii`), and background colour from `AppColors`. Examples: dashboard stat grid, file list entries, storage device cards.

**StatTile for metrics:** Dashboard uses `StatTile` widgets in a grid (aspect ratio 1.25) showing icon + label + value. Each tile watches a provider for its data.

**FolderView as full browser:** `FolderView` (~730 lines) is a reusable file browser widget with breadcrumb navigation, upload FAB, sort controls, and paginated listing. Used by both the Files screen (inline) and Folder View screen (full-page). Accepts `initialPath` and optional `onBack` callback.

---

## Animation Patterns

**flutter_animate:** Used for entrance animations on screen transitions. Common pattern:
```dart
child.animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0)
```

Applied to list items, cards, and screen content. Stagger delays for list items:
```dart
.animate(delay: (index * 50).ms)
```

---

## Error Handling

**friendlyError() in .when():**
```dart
provider.when(
  data: (data) => /* success UI */,
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => Text(friendlyError(e)),
)
```

**friendlyError() in catch blocks:**
```dart
try {
  await api.doSomething();
} catch (e) {
  _showSnack('Action failed: ${friendlyError(e)}');
}
```

**Never raw exceptions:** `friendlyError()` converts `SocketException` → "Cannot reach device", `TimeoutException` → "Request timed out", `FormatException` → "Unexpected response", and falls back to a generic message. Never show `$e` or `e.toString()`.

---

## Loading State Patterns

**AsyncValue.when() triple:** Every `FutureProvider` and `StreamProvider` consumer uses the `.when()` pattern with all three branches:
- `data:` — render content
- `loading:` — `CircularProgressIndicator` or shimmer
- `error:` — `Text(friendlyError(e))` with optional retry button

**Refresh pattern:** Pull-to-refresh calls `ref.invalidate(provider)` then reads again:
```dart
onRefresh: () async {
  ref.invalidate(familyUsersProvider);
  await ref.read(familyUsersProvider.future);
}
```

---

## Navigation Patterns

**go vs push:**
- `context.go('/dashboard')` — replaces the stack (used for tab switches and auth redirects)
- `context.push('/family')` — pushes on top (used for detail screens that should have back navigation)

**ShellRoute pattern:** The 3 main tabs are children of a `ShellRoute` that provides `MainShell` (bottom nav + disconnected banner). Child routes render inside the shell's body.

**Extra data passing:** GoRouter `extra` parameter passes objects to detail screens:
```dart
context.push('/file-preview', extra: fileItem);
```

**Auth redirect:** `splash_screen.dart` checks auth state and `go()`s to either `/scan-network` (no setup), `/user-picker` (setup done, need login), or `/dashboard` (fully authenticated).

---

## Form Patterns

**TextEditingController + dialog:**
```dart
final controller = TextEditingController();
// In dialog:
TextField(controller: controller, decoration: ...);
// On confirm:
final value = controller.text.trim();
if (value.isNotEmpty) { /* call API */ }
controller.dispose();
```

Used for: device rename, folder create, family member add, PIN entry.

**PIN entry:** Uses a row of `TextField` widgets with `maxLength: 1` and auto-focus-next, reading all values on submit.

---

## Theme Usage

**Colours:** Always use `AppColors.xxx` — never hex literals:
```dart
color: AppColors.surface        // card backgrounds
color: AppColors.primary        // accent/action colour
color: AppColors.textSecondary  // muted text
```

**Radii:** Always use `CubieRadii.xxx` for border radius:
```dart
borderRadius: BorderRadius.circular(CubieRadii.md)
```

**Fonts:** Google Fonts applied via `AppTheme`:
- Headings: Sora
- Body: DM Sans

---

## Provider Wiring

**ConsumerWidget pattern:** Most screens extend `ConsumerWidget`:
```dart
class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(systemStatsStreamProvider);
    return stats.when(...);
  }
}
```

**ConsumerStatefulWidget:** Used when local state is needed alongside providers (e.g., `TextEditingController`, animation controllers):
```dart
class TelegramSetupScreen extends ConsumerStatefulWidget { ... }
class _TelegramSetupScreenState extends ConsumerState<TelegramSetupScreen> { ... }
```

**Invalidation after mutation:** After API calls that change server state, invalidate the relevant provider to trigger re-fetch:
```dart
await api.addFamilyUser(name);
ref.invalidate(familyUsersProvider);
```