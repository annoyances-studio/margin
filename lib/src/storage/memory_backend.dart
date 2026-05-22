// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'storage_backend.dart';
import 'storage_entry.dart';
import 'storage_exception.dart';

/// An in-memory [StorageBackend]. Directories are implicit (a directory exists
/// when some file has it as a prefix).
///
/// Useful for tests and ephemeral, never-persisted repositories. Paths are
/// repository-relative, forward-slash, and `..` is rejected like other
/// backends.
class MemoryBackend implements StorageBackend {
  final Map<String, _Entry> _files = {};

  /// Injectable clock so tests can control modification times.
  final DateTime Function() _clock;

  MemoryBackend({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  List<String> _segments(String path) {
    final cleaned = path.replaceAll('\\', '/');
    final segments =
        cleaned.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (segments.contains('..')) {
      throw InvalidPathException(path, 'Path may not contain ".." segments');
    }
    return segments;
  }

  String _key(String path) => _segments(path).join('/');

  @override
  Future<List<StorageEntry>> list(String path) async {
    final prefixSegments = _segments(path);
    final prefix = prefixSegments.join('/');

    // The root always exists; any other path must be an existing directory.
    if (prefix.isNotEmpty && !_directoryExists(prefix)) {
      throw NotFoundException(path);
    }

    final folders = <String>{};
    final entries = <StorageEntry>[];

    for (final fileEntry in _files.entries) {
      final fileSegments = fileEntry.key.split('/');
      if (fileSegments.length <= prefixSegments.length) continue;
      // Must sit under the prefix.
      var matchesPrefix = true;
      for (var i = 0; i < prefixSegments.length; i++) {
        if (fileSegments[i] != prefixSegments[i]) {
          matchesPrefix = false;
          break;
        }
      }
      if (!matchesPrefix) continue;

      final childName = fileSegments[prefixSegments.length];
      final childPath =
          [...prefixSegments, childName].join('/');
      final isDirectChild = fileSegments.length == prefixSegments.length + 1;

      if (isDirectChild) {
        entries.add(StorageEntry(
          path: childPath,
          isDirectory: false,
          modified: fileEntry.value.modified,
          size: fileEntry.value.bytes.length,
        ));
      } else if (folders.add(childPath)) {
        entries.add(StorageEntry(path: childPath, isDirectory: true));
      }
    }

    return entries;
  }

  bool _directoryExists(String prefix) {
    final prefixWithSlash = '$prefix/';
    return _files.keys.any((k) => k.startsWith(prefixWithSlash));
  }

  @override
  Future<bool> exists(String path) async {
    final key = _key(path);
    if (key.isEmpty) return true; // root
    if (_files.containsKey(key)) return true;
    return _directoryExists(key);
  }

  @override
  Future<Uint8List> read(String path) async {
    final key = _key(path);
    final entry = _files[key];
    if (entry == null) {
      if (_directoryExists(key)) {
        throw InvalidPathException(path, 'Path is a directory, not a file');
      }
      throw NotFoundException(path);
    }
    return Uint8List.fromList(entry.bytes);
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final key = _key(path);
    if (key.isEmpty) {
      throw InvalidPathException(path, 'Cannot write to the repository root');
    }
    _files[key] = _Entry(Uint8List.fromList(bytes), _clock());
  }

  @override
  Future<void> delete(String path) async {
    final key = _key(path);
    if (key.isEmpty) {
      throw InvalidPathException(path, 'Cannot delete the repository root');
    }
    if (_files.remove(key) != null) return;
    // Directory: remove everything beneath it.
    final prefix = '$key/';
    _files.removeWhere((k, _) => k.startsWith(prefix));
  }
}

class _Entry {
  final Uint8List bytes;
  final DateTime modified;
  _Entry(this.bytes, this.modified);
}
