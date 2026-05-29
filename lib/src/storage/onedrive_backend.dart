// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The constructor takes a public-named accessToken param stored in a private
// field; the lint's rewrite would push a leading underscore into the call site.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'storage_backend.dart';
import 'storage_entry.dart';
import 'storage_exception.dart';

/// Supplies a valid OneDrive access token, refreshing as needed. In production
/// this is [OneDriveAuth.accessToken]; tests pass a constant.
typedef AccessTokenProvider = Future<String> Function();

/// A [StorageBackend] backed by Microsoft Graph (OneDrive), so a remote Folio
/// works on every platform the app speaks Graph from — no OS mount required.
///
/// Operations are addressed by path relative to a [rootPath] (the OneDrive
/// folder the user chose to hold the Folio). The app remains a dumb client; the
/// drive holds the same plain files. Built on an injectable [http.Client] and a
/// token provider, so it is fully unit-testable with a mock client.
///
/// This sits below the content/codec layer: it moves at-rest bytes as-is and
/// applies no encryption (the sync/content layers own that).
class OneDriveBackend implements StorageBackend {
  static const String _graphBase = 'https://graph.microsoft.com/v1.0';

  /// Graph uploads larger than 4 MiB must use an upload session.
  static const int _simpleUploadLimit = 4 * 1024 * 1024;

  /// The Folio root within the user's OneDrive, as a drive-relative path with
  /// no leading/trailing slash (e.g. `Apps/Margin/Notes`). Empty means the
  /// drive root itself.
  final String rootPath;

  final AccessTokenProvider _accessToken;
  final http.Client _client;
  final Duration timeout;

  /// Max attempts when Graph throttles (429) or is briefly unavailable (503).
  final int maxRetries;

  OneDriveBackend({
    required String rootPath,
    required AccessTokenProvider accessToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  })  : rootPath = _clean(rootPath),
        _accessToken = accessToken,
        _client = client ?? http.Client();

  static String _clean(String path) =>
      path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).join('/');

  /// Splits a repo-relative path into clean segments, rejecting `..`.
  List<String> _segments(String path) {
    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (segments.contains('..')) {
      throw InvalidPathException(path, 'Path may not contain ".." segments');
    }
    return segments;
  }

  /// Combines [rootPath] with a repo-relative [path] into a drive-relative path.
  String _abs(String path) {
    final rel = _segments(path).join('/');
    if (rootPath.isEmpty) return rel;
    return rel.isEmpty ? rootPath : '$rootPath/$rel';
  }

  /// URL-encodes a drive-relative path for Graph's `root:/{path}:` addressing
  /// (each segment encoded; `/` separators preserved). Handles non-ASCII names
  /// (e.g. Japanese) correctly.
  String _encodePath(String absPath) => absPath
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');

  Uri _itemUri(String absPath) {
    final encoded = _encodePath(absPath);
    return Uri.parse(
      encoded.isEmpty ? '$_graphBase/me/drive/root' : '$_graphBase/me/drive/root:/$encoded',
    );
  }

  Uri _childrenUri(String absPath) {
    final encoded = _encodePath(absPath);
    return Uri.parse(
      encoded.isEmpty
          ? '$_graphBase/me/drive/root/children'
          : '$_graphBase/me/drive/root:/$encoded:/children',
    );
  }

  Uri _contentUri(String absPath) =>
      Uri.parse('$_graphBase/me/drive/root:/${_encodePath(absPath)}:/content');

  Uri _uploadSessionUri(String absPath) => Uri.parse(
      '$_graphBase/me/drive/root:/${_encodePath(absPath)}:/createUploadSession');

  bool _ok(int status) => status >= 200 && status < 300;

  /// Sends a Graph request with a bearer token, a timeout, and polite backoff
  /// on throttling (429) / transient unavailability (503), honoring Retry-After.
  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    for (var attempt = 0;; attempt++) {
      final token = await _accessToken();
      final request = http.Request(method, uri)
        ..headers['authorization'] = 'Bearer $token'
        ..headers.addAll(headers);
      if (body != null) request.bodyBytes = body;

      final http.Response response;
      try {
        final streamed = await _client.send(request).timeout(timeout);
        response = await http.Response.fromStream(streamed).timeout(timeout);
      } on TimeoutException {
        throw StorageException(
          '$method timed out after ${timeout.inSeconds}s',
          path: uri.toString(),
        );
      }

      if ((response.statusCode == 429 || response.statusCode == 503) &&
          attempt < maxRetries) {
        await Future<void>.delayed(_retryDelay(response, attempt));
        continue;
      }
      return response;
    }
  }

  /// Honors a `Retry-After` header (seconds) when present; otherwise backs off
  /// exponentially (1s, 2s, 4s, …).
  Duration _retryDelay(http.Response response, int attempt) {
    final header = response.headers['retry-after'];
    final seconds = header == null ? null : int.tryParse(header.trim());
    if (seconds != null) return Duration(seconds: seconds);
    return Duration(seconds: 1 << attempt);
  }

  @override
  Future<Uint8List> read(String path) async {
    final res = await _send('GET', _contentUri(_abs(path)));
    if (res.statusCode == 404) throw NotFoundException(path);
    if (_ok(res.statusCode)) return res.bodyBytes;
    throw StorageException('GET content failed (${res.statusCode})', path: path);
  }

  @override
  Future<bool> exists(String path) async {
    final abs = _abs(path);
    // The Folio root always "exists" (it is the drive root or a folder we open
    // into); avoid an item lookup that would 404 at the drive root.
    if (abs.isEmpty) return true;
    final res = await _send('GET', _itemUri(abs));
    if (res.statusCode == 404) return false;
    if (_ok(res.statusCode)) return true;
    throw StorageException('GET item failed (${res.statusCode})', path: path);
  }

  @override
  Future<List<StorageEntry>> list(String path) async {
    final entries = <StorageEntry>[];
    Uri? next = _childrenUri(_abs(path));
    final base = _segments(path).join('/');

    while (next != null) {
      final res = await _send('GET', next);
      if (res.statusCode == 404) throw NotFoundException(path);
      if (!_ok(res.statusCode)) {
        throw StorageException('list failed (${res.statusCode})', path: path);
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      for (final item in (json['value'] as List).cast<Map<String, dynamic>>()) {
        final name = item['name'] as String;
        final isDir = item.containsKey('folder');
        entries.add(StorageEntry(
          path: base.isEmpty ? name : '$base/$name',
          isDirectory: isDir,
          size: isDir ? null : (item['size'] as num?)?.toInt(),
          modified: _parseDate(item['lastModifiedDateTime']),
        ));
      }
      final link = json['@odata.nextLink'] as String?;
      next = link == null ? null : Uri.parse(link);
    }
    return entries;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (_segments(path).isEmpty) {
      throw InvalidPathException(path, 'Cannot write to the Folio root');
    }
    final abs = _abs(path);
    await _ensureParents(path);
    if (bytes.length < _simpleUploadLimit) {
      await _simpleUpload(abs, bytes, path);
    } else {
      await _sessionUpload(abs, bytes, path);
    }
  }

  Future<void> _simpleUpload(String abs, Uint8List bytes, String path) async {
    final res = await _send(
      'PUT',
      _contentUri(abs),
      headers: const {'content-type': 'application/octet-stream'},
      body: bytes,
    );
    if (_ok(res.statusCode)) return;
    throw StorageException('upload failed (${res.statusCode})', path: path);
  }

  /// Uploads a large file via an upload session. For simplicity the whole file
  /// is sent as a single fragment (Graph allows up to 60 MiB per fragment),
  /// which covers any realistic note attachment.
  Future<void> _sessionUpload(String abs, Uint8List bytes, String path) async {
    final create = await _send(
      'POST',
      _uploadSessionUri(abs),
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode({
        'item': {'@microsoft.graph.conflictBehavior': 'replace'},
      })),
    );
    if (!_ok(create.statusCode)) {
      throw StorageException(
        'createUploadSession failed (${create.statusCode})',
        path: path,
      );
    }
    final uploadUrl =
        (jsonDecode(create.body) as Map<String, dynamic>)['uploadUrl'] as String;
    final total = bytes.length;
    // The upload URL is pre-authenticated; no bearer token on the fragment PUT.
    final res = await _client
        .put(
          Uri.parse(uploadUrl),
          headers: {
            'content-length': '$total',
            'content-range': 'bytes 0-${total - 1}/$total',
          },
          body: bytes,
        )
        .timeout(timeout);
    if (!_ok(res.statusCode)) {
      throw StorageException('upload fragment failed (${res.statusCode})',
          path: path);
    }
  }

  @override
  Future<void> delete(String path) async {
    if (_segments(path).isEmpty) {
      throw InvalidPathException(path, 'Cannot delete the Folio root');
    }
    final res = await _send('DELETE', _itemUri(_abs(path)));
    if (res.statusCode == 404 || _ok(res.statusCode)) return; // 404 = no-op
    throw StorageException('DELETE failed (${res.statusCode})', path: path);
  }

  /// Ensures the Folio root folder (and its ancestors) exist on the drive.
  /// Used before creating a new Folio in a folder the user named that may not
  /// exist yet. No-op when the root is the drive root.
  Future<void> ensureRoot() async {
    final segs = rootPath.split('/').where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < segs.length; i++) {
      await _createFolder(segs.sublist(0, i).join('/'), segs[i]);
    }
  }

  /// Creates any missing folders between the Folio root and [relPath] (Graph
  /// won't auto-create the path on upload). The root itself is assumed to exist
  /// (it was chosen/created via the picker), so we only create folders below it.
  Future<void> _ensureParents(String relPath) async {
    final relSegs = _segments(relPath);
    for (var i = 0; i < relSegs.length - 1; i++) {
      final parentAbs = _abs(relSegs.sublist(0, i).join('/'));
      await _createFolder(parentAbs, relSegs[i]);
    }
  }

  Future<void> _createFolder(String parentAbs, String name) async {
    final res = await _send(
      'POST',
      _childrenUri(parentAbs),
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode({
        'name': name,
        'folder': <String, dynamic>{},
        // Don't clobber an existing folder; a 409 just means it's already there.
        '@microsoft.graph.conflictBehavior': 'fail',
      })),
    );
    if (_ok(res.statusCode) || res.statusCode == 409) return;
    throw StorageException(
      'create folder failed (${res.statusCode})',
      path: parentAbs.isEmpty ? name : '$parentAbs/$name',
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}
