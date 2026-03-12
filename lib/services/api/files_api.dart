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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/list')
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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/mkdir'),
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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/delete')
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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/rename'),
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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/download')
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
    return '$_baseUrl${AppConstants.apiVersion}/files/download?path=${Uri.encodeComponent(filePath)}';
  }

  /// Returns auth headers for use in image widgets.
  Map<String, String> get authHeaders => _headers;

  /// POST /api/v1/files/upload (multipart/form-data)
  /// Uploads a real file from [filePath] to [destinationPath] on the NAS.
  ///
  /// Returns a stream of uploaded byte counts. Each event is the cumulative
  /// number of multipart-body bytes delivered to the socket so far, enabling
  /// real percentage progress (divide by [totalBytes]).
  Stream<int> uploadFile(
      String destinationPath, String fileName, int totalBytes,
      {String? filePath, Completer<String?>? sortedToCompleter}) {
    final ctrl = StreamController<int>();

    () async {
      try {
        final uri =
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/upload')
                .replace(queryParameters: {'path': destinationPath});

        // Build a MultipartRequest to derive the Content-Type header (which
        // carries the boundary string) and the exact content length.
        final multipart = http.MultipartRequest('POST', uri);
        final token = _session?.token;
        if (token != null) {
          multipart.headers['Authorization'] = 'Bearer $token';
        }

        if (filePath != null) {
          multipart.files.add(
            await http.MultipartFile.fromPath('file', filePath,
                filename: fileName),
          );
        } else {
          multipart.files.add(http.MultipartFile.fromBytes(
            'file',
            [],
            filename: fileName,
          ));
        }

        final contentLength = multipart.contentLength;

        // Wrap the finalized body stream with a byte counter so we can emit
        // cumulative progress events as chunks are handed to the socket.
        int bytesSent = 0;
        final bodyStream = multipart.finalize().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              bytesSent += chunk.length;
              ctrl.add(bytesSent);
              sink.add(chunk);
            },
          ),
        );

        // Construct a StreamedRequest carrying the multipart Content-Type so
        // the server can find the boundary and parse the body correctly.
        final streamedRequest = http.StreamedRequest('POST', uri)
          ..contentLength = contentLength
          ..headers.addAll(multipart.headers);

        // Pipe the progress-tracked body into the request sink.
        bodyStream.listen(
          streamedRequest.sink.add,
          onDone: streamedRequest.sink.close,
          onError: (Object e) => streamedRequest.sink.addError(e),
          cancelOnError: true,
        );

        final response = await _client.send(streamedRequest);
        final responseBody = await response.stream.bytesToString();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          // Extract the sortedTo folder from the JSON response if requested.
          if (sortedToCompleter != null) {
            try {
              final json = jsonDecode(responseBody) as Map<String, dynamic>;
              sortedToCompleter.complete(json['sortedTo'] as String?);
            } catch (_) {
              sortedToCompleter.complete(null);
            }
          }
          ctrl.add(totalBytes); // guarantee a 100 % event
          await ctrl.close();
        } else {
          sortedToCompleter?.complete(null);
          ctrl.addError(Exception('Upload failed: ${response.statusCode}'));
          await ctrl.close();
        }
      } catch (e) {
        sortedToCompleter?.complete(null);
        ctrl.addError(e);
        await ctrl.close();
      }
    }();

    return ctrl.stream;
  }

  /// GET /api/v1/files/search?q=<query> — full-text document search (FTS5).
  Future<List<SearchResult>> searchDocuments(String query) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/search')
                .replace(queryParameters: {'q': query, 'limit': '10'}),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final Map<String, dynamic> body = jsonDecode(res.body);
    final List<dynamic> list = body['results'] as List<dynamic>;
    return list
        .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/v1/files/trash — list the caller's trash items.
  Future<List<TrashItem>> getTrashItems() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/trash'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TrashItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/v1/files/trash/{id}/restore — restore an item to its original path.
  Future<void> restoreTrashItem(String id) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/files/trash/${Uri.encodeComponent(id)}/restore'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/files/trash/{id} — permanently delete a trash item.
  Future<void> permanentDeleteTrashItem(String id) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/files/trash/${Uri.encodeComponent(id)}'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/files/trash/prefs — return whether 30-day auto-delete is enabled.
  Future<bool> getTrashAutoDelete() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/trash/prefs'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['autoDelete'] as bool? ?? false;
  }

  /// PUT /api/v1/files/trash/prefs — enable or disable 30-day auto-delete.
  Future<void> setTrashAutoDelete(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/trash/prefs'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'autoDelete': enabled}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/files/roots — returns mounted USB/NVMe drives as browseable roots.
  Future<List<StorageRoot>> getStorageRoots() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/roots'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final Map<String, dynamic> body = jsonDecode(res.body);
    final List<dynamic> list = body['roots'] as List<dynamic>;
    return list
        .map((item) =>
            StorageRoot.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
