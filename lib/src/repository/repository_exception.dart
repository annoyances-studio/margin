// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Base class for errors raised when opening or creating a [Repository].
class RepositoryException implements Exception {
  final String message;

  const RepositoryException(this.message);

  @override
  String toString() => 'RepositoryException: $message';
}

/// Thrown when the target location is not a Margin repository: there is no root
/// `properties.yaml`, or it is malformed / missing required fields.
class NotAMarginRepositoryException extends RepositoryException {
  const NotAMarginRepositoryException(super.message);
}

/// Thrown when creating a repository where one already exists.
class RepositoryExistsException extends RepositoryException {
  const RepositoryExistsException(super.message);
}

/// Thrown when a repository's schema version is newer than this build supports,
/// so it should not be opened (it may have been created by a newer app).
class IncompatibleSchemaException extends RepositoryException {
  final int found;
  final int supported;

  IncompatibleSchemaException(this.found, this.supported)
      : super('Repository schema version $found is newer than the '
            'supported version $supported');
}
