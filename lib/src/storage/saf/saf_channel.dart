// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';

import '../storage_entry.dart';
import '../storage_exception.dart';

/// The bridge to Android's Storage Access Framework — a folder the user grants
/// once via the system picker, then read over a `content://` tree URI. Kept as
/// an interface so [SafBackend] and the controller are testable with a fake
/// (the real one talks to native code, which unit tests can't).
abstract interface class SafChannel {
  /// Shows the system folder picker. Returns the granted tree URI and its
  /// display name, or null if the user cancelled. Read permission is persisted
  /// natively so the URI can be reopened later.
  Future<({String uri, String name})?> pickFolder();

  /// Immediate children of [path] (repo-relative, forward slashes; `''` = the
  /// granted root) under [treeUri]. Throws [NotFoundException] if missing.
  Future<List<StorageEntry>> list(String treeUri, String path);

  /// Bytes of the file at [path]. Throws [NotFoundException] if missing.
  Future<Uint8List> read(String treeUri, String path);

  /// Whether anything exists at [path].
  Future<bool> exists(String treeUri, String path);
}

/// The real [SafChannel], over the `margin/app` platform channel (Android).
class MethodChannelSaf implements SafChannel {
  const MethodChannelSaf();

  static const MethodChannel _channel = MethodChannel('margin/app');

  @override
  Future<({String uri, String name})?> pickFolder() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('safPickFolder');
    final uri = res?['uri'] as String?;
    if (uri == null) return null;
    return (uri: uri, name: res?['name'] as String? ?? 'Folder');
  }

  @override
  Future<List<StorageEntry>> list(String treeUri, String path) async {
    final raw = await _channel.invokeListMethod<dynamic>(
      'safList',
      {'uri': treeUri, 'path': path},
    );
    if (raw == null) throw NotFoundException(path);
    return [
      for (final e in raw.cast<Map>())
        StorageEntry(
          path: path.isEmpty ? e['name'] as String : '$path/${e['name']}',
          isDirectory: e['isDir'] == true,
          size: (e['size'] as num?)?.toInt(),
          modified: e['modified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch((e['modified'] as num).toInt()),
        ),
    ];
  }

  @override
  Future<Uint8List> read(String treeUri, String path) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'safRead',
      {'uri': treeUri, 'path': path},
    );
    if (bytes == null) throw NotFoundException(path);
    return bytes;
  }

  @override
  Future<bool> exists(String treeUri, String path) async {
    final res = await _channel.invokeMethod<bool>(
      'safExists',
      {'uri': treeUri, 'path': path},
    );
    return res ?? false;
  }
}
