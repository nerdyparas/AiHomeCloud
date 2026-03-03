import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../../widgets/folder_view.dart';

/// Tab 2 — personal file browser for the current user.
class MyFolderScreen extends ConsumerWidget {
  const MyFolderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final user = (session?.username.isNotEmpty ?? false)
      ? session!.username
      : 'user';
    final path = '${CubieConstants.personalBasePath}$user/';

    return FolderView(
      title: 'My Files',
      folderPath: path,
      readOnly: false,
    );
  }
}
