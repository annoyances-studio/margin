// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'storage_backend.dart';
import 'storage_entry.dart';
import 'storage_exception.dart';

/// A [StorageBackend] backed by a directory on the local filesystem.
///
/// This is the zero-config default backend (DESIGN.md). Repository-relative
/// forward-slash paths are mapped onto [rootPath] using the host's path
/// separator. Paths containing `..` segments are rejected so a repository can
/// never read or write outside its own root.
class LocalFolderBackend implements StorageBackend {
  /// Absolute path to the directory that serves as the repository root.
  final String rootPath;

  LocalFolderBackend(String rootPath) : rootPath = p.normalize(rootPath);

  /// The absolute on-disk path for a repository-relative [path]. Useful for
  /// revealing a file or folder in the OS file manager.
  String absolutePathOf(String path) => _resolve(path);

  /// Resolves a repository-relative [path] to an absolute local path,
  /// rejecting `..` traversal and backslash separators.
  String _resolve(String path) {
    final cleaned = path.replaceAll('\\', '/');
    final segments =
        cleaned.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (segments.contains('..')) {
      throw InvalidPathException(path, 'Path may not contain ".." segments');
    }
    return p.normalize(p.joinAll([rootPath, ...segments]));
  }

  /// Converts an absolute local path back to a repository-relative,
  /// forward-slash path.
  String _toRelativePosix(String absoluteLocalPath) {
    final rel = p.relative(absoluteLocalPath, from: rootPath);
    return p.split(rel).join('/');
  }

  @override
  Future<List<StorageEntry>> list(String path) async {
    final dir = Directory(_resolve(path));
    if (!await dir.exists()) {
      throw NotFoundException(path);
    }
    final entries = <StorageEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final stat = await entity.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      entries.add(StorageEntry(
        path: _toRelativePosix(entity.path),
        isDirectory: isDir,
        modified: stat.modified,
        size: isDir ? null : stat.size,
      ));
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<bool> exists(String path) async {
    final type =
        await FileSystemEntity.type(_resolve(path), followLinks: false);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<Uint8List> read(String path) async {
    final resolved = _resolve(path);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw NotFoundException(path);
    }
    if (type == FileSystemEntityType.directory) {
      throw InvalidPathException(path, 'Path is a directory, not a file');
    }
    return File(resolved).readAsBytes();
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final file = File(_resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    final resolved = _resolve(path);
    if (resolved == rootPath) {
      throw InvalidPathException(path, 'Cannot delete the repository root');
    }
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    switch (type) {
      case FileSystemEntityType.notFound:
        return; // no-op
      case FileSystemEntityType.directory:
        await Directory(resolved).delete(recursive: true);
      default:
        await File(resolved).delete();
    }
  }
}
