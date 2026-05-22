// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Base class for errors raised by a [StorageBackend].
class StorageException implements Exception {
  final String message;
  final String? path;

  const StorageException(this.message, {this.path});

  @override
  String toString() =>
      'StorageException: $message${path != null ? ' (path: $path)' : ''}';
}

/// Thrown when a requested path does not exist.
class NotFoundException extends StorageException {
  const NotFoundException(String path)
      : super('No such file or directory', path: path);
}

/// Thrown when a path is invalid — for example it would resolve outside the
/// backend's root, contains `..` segments, or is a directory where a file was
/// expected.
class InvalidPathException extends StorageException {
  const InvalidPathException(String path, [String? reason])
      : super(reason ?? 'Invalid path', path: path);
}
