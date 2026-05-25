// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'storage_backend.dart';
import 'storage_entry.dart';
import 'storage_exception.dart';

/// A [StorageBackend] that speaks WebDAV directly over HTTP, so it works on
/// every platform without the OS mounting anything (DESIGN.md). The app is a
/// dumb client; the remote holds the same plain files.
///
/// Built on an injectable [http.Client] so it is fully unit-testable with a
/// mock client (no server required). Credentials, when supplied, are sent as
/// HTTP Basic auth; higher layers source them from the OS keystore — never from
/// the repository itself.
class WebDavBackend implements StorageBackend {
  /// The collection root on the server, always ending in `/`
  /// (e.g. `https://host/remote.php/dav/files/me/Notes/`).
  final Uri baseUrl;

  final http.Client _client;
  final Map<String, String> _authHeaders;

  WebDavBackend({
    required Uri baseUrl,
    String? username,
    String? password,
    http.Client? client,
  })  : baseUrl = _withTrailingSlash(baseUrl),
        _client = client ?? http.Client(),
        _authHeaders = _basicAuth(username, password);

  static Uri _withTrailingSlash(Uri url) =>
      url.path.endsWith('/') ? url : url.replace(path: '${url.path}/');

  static Map<String, String> _basicAuth(String? user, String? pass) {
    if (user == null || pass == null) return const {};
    final token = base64.encode(utf8.encode('$user:$pass'));
    return {'authorization': 'Basic $token'};
  }

  /// Splits a repository-relative path into clean segments, rejecting `..`
  /// (matching the other backends).
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

  /// Builds the absolute URL for [path]. Directories get a trailing slash, as
  /// WebDAV servers expect for collections. Segment encoding is handled by
  /// [Uri.replace] (so spaces, Unicode, etc. round-trip correctly).
  Uri _resolve(String path, {bool directory = false}) {
    final segments = _segments(path);
    if (segments.isEmpty) return baseUrl; // root already ends in '/'
    final base = baseUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    final all = [...base, ...segments];
    if (directory) all.add(''); // empty trailing segment => trailing slash
    return baseUrl.replace(pathSegments: all);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(_authHeaders)
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(await _client.send(request));
  }

  bool _ok(int status) => status >= 200 && status < 300;

  @override
  Future<Uint8List> read(String path) async {
    final res = await _send('GET', _resolve(path));
    if (res.statusCode == 404) throw NotFoundException(path);
    if (_ok(res.statusCode)) return res.bodyBytes;
    throw StorageException('GET failed (${res.statusCode})', path: path);
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (_segments(path).isEmpty) {
      throw InvalidPathException(path, 'Cannot write to the repository root');
    }
    await _ensureParents(path);
    final res = await _send('PUT', _resolve(path), body: bytes);
    if (_ok(res.statusCode)) return;
    throw StorageException('PUT failed (${res.statusCode})', path: path);
  }

  /// Creates any missing parent collections (WebDAV PUT won't create them).
  Future<void> _ensureParents(String path) async {
    final segments = _segments(path);
    for (var i = 1; i < segments.length; i++) {
      final dir = segments.take(i).join('/');
      final res = await _send('MKCOL', _resolve(dir, directory: true));
      // 201 = created; 405/301 = already exists. Anything else: let the
      // subsequent PUT surface the real error.
      if (!_ok(res.statusCode) &&
          res.statusCode != 405 &&
          res.statusCode != 301) {
        // Non-fatal here; PUT will fail loudly if the parent truly is missing.
      }
    }
  }

  @override
  Future<void> delete(String path) async {
    if (_segments(path).isEmpty) {
      throw InvalidPathException(path, 'Cannot delete the repository root');
    }
    final res = await _send('DELETE', _resolve(path));
    if (res.statusCode == 404 || _ok(res.statusCode)) return; // 404 = no-op
    throw StorageException('DELETE failed (${res.statusCode})', path: path);
  }

  @override
  Future<bool> exists(String path) async {
    final res = await _propfind(_resolve(path), depth: 0);
    if (res.statusCode == 404) return false;
    if (res.statusCode == 207) return true;
    throw StorageException('PROPFIND failed (${res.statusCode})', path: path);
  }

  @override
  Future<List<StorageEntry>> list(String path) async {
    final res = await _propfind(_resolve(path, directory: true), depth: 1);
    if (res.statusCode == 404) throw NotFoundException(path);
    if (res.statusCode != 207) {
      throw StorageException('PROPFIND failed (${res.statusCode})', path: path);
    }
    return _parseMultistatus(res.body);
  }

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<propfind xmlns="DAV:"><prop>'
      '<resourcetype/><getcontentlength/><getlastmodified/>'
      '</prop></propfind>';

  Future<http.Response> _propfind(Uri uri, {required int depth}) => _send(
        'PROPFIND',
        uri,
        headers: {
          'depth': '$depth',
          'content-type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(_propfindBody),
      );

  /// Parses a WebDAV multistatus body into entries, relative to the repo root.
  /// The collection's own entry (which PROPFIND Depth:1 includes first) is
  /// skipped. Element lookups ignore namespace prefixes (servers vary).
  List<StorageEntry> _parseMultistatus(String body) {
    final baseSegments =
        baseUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    final entries = <StorageEntry>[];

    for (final response in _local(XmlDocument.parse(body), 'response')) {
      final href = _localText(response, 'href');
      if (href == null) continue;

      final hrefSegments =
          Uri.parse(href).pathSegments.where((s) => s.isNotEmpty).toList();
      if (hrefSegments.length <= baseSegments.length) continue; // the root
      final relSegments = hrefSegments.sublist(baseSegments.length);
      final relPath = relSegments.join('/');

      final isDirectory = _local(response, 'collection').isNotEmpty;
      final lengthText = _localText(response, 'getcontentlength');
      final modifiedText = _localText(response, 'getlastmodified');

      entries.add(StorageEntry(
        path: relPath,
        isDirectory: isDirectory,
        size: isDirectory ? null : int.tryParse(lengthText ?? ''),
        modified: _parseHttpDate(modifiedText),
      ));
    }
    return entries;
  }

  static Iterable<XmlElement> _local(XmlNode root, String name) =>
      root.descendants.whereType<XmlElement>().where(
            (e) => e.name.local == name,
          );

  static String? _localText(XmlNode root, String name) {
    final element = _local(root, name).firstOrNull;
    final text = element?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null) return null;
    try {
      return HttpDate.parse(value).toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}
