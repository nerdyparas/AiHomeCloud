import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/constants.dart';
import 'api_service.dart';
import 'auth_session.dart';

// ── Upload progress state ─────────────────────────────────────────────────────

/// Immutable snapshot of an in-progress or just-completed share upload batch.
class ShareUploadState {
  final bool active;
  final int done;
  final int total;

  const ShareUploadState({
    this.active = false,
    this.done = 0,
    this.total = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShareUploadState &&
          active == other.active &&
          done == other.done &&
          total == other.total;

  @override
  int get hashCode => Object.hash(active, done, total);
}

class ShareUploadNotifier extends StateNotifier<ShareUploadState> {
  ShareUploadNotifier() : super(const ShareUploadState());

  void start(int total) =>
      state = ShareUploadState(active: true, done: 0, total: total);
  void increment(int done) =>
      state = ShareUploadState(active: true, done: done, total: state.total);
  void finish(int done) =>
      state = ShareUploadState(active: false, done: done, total: state.total);
  void clear() => state = const ShareUploadState();
}

final shareUploadProvider =
    StateNotifierProvider<ShareUploadNotifier, ShareUploadState>(
  (_) => ShareUploadNotifier(),
);

// ── ShareHandler service ──────────────────────────────────────────────────────

/// Listens for Android share intents and uploads received files to the
/// authenticated user's .inbox/ directory on the Cubie.
///
/// Initialise once from the root ConsumerStatefulWidget. Pass a [getSession]
/// closure so ShareHandler never holds a stale auth reference.
class ShareHandler {
  final ShareUploadNotifier _progress;
  /// Returns the current auth session each time it is called.
  final AuthSession? Function() _getSession;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  ShareHandler({
    required ShareUploadNotifier progress,
    required AuthSession? Function() getSession,
  })  : _progress = progress,
        _getSession = getSession;

  /// Call once from [State.initState] to start listening for share intents.
  Future<void> initialize() async {
    // Cold-start: app was launched via a share action.
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      unawaited(_handleFiles(initial));
      ReceiveSharingIntent.instance.reset();
    }

    // Hot-start: share received while the app is already open.
    _sub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleFiles, onError: (_) {});
  }

  void dispose() => _sub?.cancel();

  Future<void> _handleFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final session = _getSession();
    if (session == null) return; // Not authenticated — drop silently.

    final api = ApiService.instance;
    // Backend forces uploads into .inbox/ regardless, but we target it
    // explicitly so path-safety checks pass on the server side.
    final inboxPath =
        '${CubieConstants.personalBasePath}${session.username}/.inbox/';

    _progress.start(files.length);
    var done = 0;

    for (final shared in files) {
      try {
        final f = File(shared.path);
        if (!f.existsSync()) continue;
        final name = f.uri.pathSegments.last;
        final bytes = f.lengthSync();
        await api
            .uploadFile(inboxPath, name, bytes, filePath: shared.path)
            .drain<void>();
        done++;
        _progress.increment(done);
      } catch (_) {
        // Individual file failure — continue uploading the rest.
      }
    }

    _progress.finish(done);
    // Auto-clear the banner after a brief success display.
    await Future.delayed(const Duration(seconds: 3));
    _progress.clear();
  }
}
