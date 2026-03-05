part of '../api_service.dart';

/// File operations â€” list, create folder, delete, rename, download, upload.
extension FilesApi on ApiService {
  /// GET /api/v1/files/list?path=<path>
  Future<FileListResponse> listFiles(
    String path, {
    int page = 0,
    int pageSize = 50,
    String sortBy = 'name',
    String sortDir = 'asc',
  }) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/list')
                .replace(queryParameters: {
              'path': path,
              'page': '$page',
              'page_size': '$pageSize',
              'sort_by': sortBy,
              'sort_dir': sortDir,
            }),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final Map<String, dynamic> body = jsonDecode(res.body);
    final List<dynamic> list = body['items'] as List<dynamic>;
    final items = list.map((item) {
      return FileItem(
        name: item['name'],
        path: item['path'],
        isDirectory: item['isDirectory'] as bool,
        sizeBytes: item['sizeBytes'] as int,
        modified: DateTime.parse(item['modified']),
        mimeType: item['mimeType'],
      );
    }).toList();

    return FileListResponse(
      items: items,
      totalCount: (body['totalCount'] as num?)?.toInt() ?? items.length,
      page: (body['page'] as num?)?.toInt() ?? page,
      pageSize: (body['pageSize'] as num?)?.toInt() ?? pageSize,
    );
  }

  /// POST /api/v1/files/mkdir  body: {path}
  Future<void> createFolder(String parentPath, String name) async {
    final fullPath =
        parentPath.endsWith('/') ? '$parentPath$name' : '$parentPath/$name';
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/mkdir'),
            headers: _headers,
            body: jsonEncode({'path': fullPath}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/files/delete?path=<path>
  Future<void> deleteFile(String path) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/delete')
                .replace(queryParameters: {'path': path}),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/files/rename  body: {oldPath, newName}
  Future<void> renameFile(String path, String newName) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/rename'),
            headers: _headers,
            body: jsonEncode({'oldPath': path, 'newName': newName}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/files/download?path=...
  /// Returns the raw file bytes for saving or previewing.
  Future<http.Response> downloadFile(String filePath) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/download')
                .replace(queryParameters: {'path': filePath}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 60)),
    );
    _check(res);
    return res;
  }

  /// Returns the download URL for a file (for image display etc.)
  String getDownloadUrl(String filePath) {
    return '$_baseUrl${CubieConstants.apiVersion}/files/download?path=${Uri.encodeComponent(filePath)}';
  }

  /// Returns auth headers for use in image widgets.
  Map<String, String> get authHeaders => _headers;

  /// POST /api/v1/files/upload (multipart)
  /// Uploads a real file from [filePath] to [destinationPath] on the NAS.
  /// Returns a stream of uploaded byte counts for progress tracking.
  Stream<int> uploadFile(
      String destinationPath, String fileName, int totalBytes,
      {String? filePath}) {
    final ctrl = StreamController<int>();

    () async {
      try {
        final uri =
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/upload')
                .replace(queryParameters: {'path': destinationPath});

        final request = http.MultipartRequest('POST', uri);
        final token = _session?.token;
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }

        if (filePath != null) {
          // Real file from device
          request.files.add(
            await http.MultipartFile.fromPath('file', filePath,
                filename: fileName),
          );
        } else {
          // Fallback: empty bytes (shouldn't happen in production)
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            [],
            filename: fileName,
          ));
        }

        final response = await _client.send(request);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ctrl.add(totalBytes);
          await ctrl.close();
        } else {
          ctrl.addError(Exception('Upload failed: \${response.statusCode}'));
          await ctrl.close();
        }
      } catch (e) {
        ctrl.addError(e);
        await ctrl.close();
      }
    }();

    return ctrl.stream;
  }
}
