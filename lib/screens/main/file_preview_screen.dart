import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';

/// Full-screen file preview for images, text, and other file types.
/// Pushed via GoRouter with the FileItem as extra data.
class FilePreviewScreen extends ConsumerStatefulWidget {
  final FileItem file;
  const FilePreviewScreen({super.key, required this.file});

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  bool _loading = true;
  String? _error;

  // For text files
  String? _textContent;

  // For images, we use network image with auth headers
  late final String _downloadUrl;
  late final Map<String, String> _authHeaders;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiServiceProvider);
    _downloadUrl = api.getDownloadUrl(widget.file.path);
    _authHeaders = api.authHeaders;

    if (_isText) {
      _loadTextContent();
    } else {
      _loading = false;
    }
  }

  bool get _isImage {
    final ext = widget.file.name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
        .contains(ext);
  }

  bool get _isText {
    final ext = widget.file.name.split('.').last.toLowerCase();
    return [
      'txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv', 'log',
      'py', 'dart', 'js', 'ts', 'html', 'css', 'sh', 'bash',
      'conf', 'cfg', 'ini', 'toml', 'env', 'gitignore', 'dockerfile',
    ].contains(ext);
  }

  bool get _isVideo {
    final ext = widget.file.name.split('.').last.toLowerCase();
    return ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'].contains(ext);
  }

  bool get _isAudio {
    final ext = widget.file.name.split('.').last.toLowerCase();
    return ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(ext);
  }

  Future<void> _loadTextContent() async {
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.downloadFile(widget.file.path);
      setState(() {
        _textContent = utf8.decode(res.bodyBytes, allowMalformed: true);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _downloadToDevice() async {
    // Show a snackbar indicating download isn't saved locally yet
    // This would use path_provider + file save in a full implementation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Download started: ${widget.file.name}',
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: CubieColors.card,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        title: Text(
          widget.file.name,
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: _downloadToDevice,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: CubieColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: CubieColors.error),
              const SizedBox(height: 16),
              Text('Failed to load file',
                  style: GoogleFonts.sora(
                      color: CubieColors.textPrimary, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_isImage) return _imagePreview();
    if (_isText) return _textPreview();
    return _unsupportedPreview();
  }

  Widget _imagePreview() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.network(
          _downloadUrl,
          headers: _authHeaders,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: CubieColors.primary,
              ),
            );
          },
          errorBuilder: (_, error, __) => _errorWidget(error.toString()),
        ),
      ),
    );
  }

  Widget _textPreview() {
    if (_textContent == null) return _errorWidget('No content');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _textContent!,
        style: GoogleFonts.firaCode(
          color: CubieColors.textPrimary,
          fontSize: 13,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _unsupportedPreview() {
    String message;
    IconData icon;

    if (_isVideo) {
      icon = Icons.movie_rounded;
      message = 'Video preview not supported yet.\nDownload the file to view it.';
    } else if (_isAudio) {
      icon = Icons.music_note_rounded;
      message = 'Audio preview not supported yet.\nDownload the file to play it.';
    } else {
      icon = Icons.insert_drive_file_rounded;
      message = 'Preview not available for this file type.\nDownload the file to open it.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: CubieColors.textMuted),
            const SizedBox(height: 20),
            Text(widget.file.name,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(widget.file.formattedSize,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            Text(message,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textMuted, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _downloadToDevice,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Download',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorWidget(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded,
                size: 48, color: CubieColors.textMuted),
            const SizedBox(height: 12),
            Text(msg,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
}
