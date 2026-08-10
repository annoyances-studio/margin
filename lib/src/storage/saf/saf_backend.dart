// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import '../storage_backend.dart';
import '../storage_entry.dart';
import 'saf_channel.dart';

/// A read-only [StorageBackend] over an Android SAF folder the user granted via
/// the system picker — the access model companion mode needs on Android, where
/// scoped storage forbids reading arbitrary paths with `dart:io`.
///
/// Read-only by design (companion mode never writes): [write] and [delete]
/// throw. Reads/lists delegate to the native [SafChannel]; repo-relative paths
/// (root `''` or `/`) are normalised to what the channel expects.
class SafBackend implements StorageBackend {
  final SafChannel _saf;

  /// The granted `content://` tree URI (also the recent-Folios `location`).
  final String treeUri;

  const SafBackend(this._saf, this.treeUri);

  @override
  Future<List<StorageEntry>> list(String path) => _saf.list(treeUri, _rel(path));

  @override
  Future<bool> exists(String path) => _saf.exists(treeUri, _rel(path));

  @override
  Future<Uint8List> read(String path) => _saf.read(treeUri, _rel(path));

  @override
  Future<void> write(String path, Uint8List bytes) =>
      throw UnsupportedError('SafBackend is read-only (companion mode)');

  @override
  Future<void> delete(String path) =>
      throw UnsupportedError('SafBackend is read-only (companion mode)');

  /// Normalises a backend path (root is `''` or `/`, may have a leading slash)
  /// to the plain relative form the channel uses (`''` for the root).
  String _rel(String path) => path.replaceAll(RegExp(r'^/+'), '');
}
