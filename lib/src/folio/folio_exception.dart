// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Base class for errors raised when opening or creating a [Folio].
class FolioException implements Exception {
  final String message;

  const FolioException(this.message);

  @override
  String toString() => 'FolioException: $message';
}

/// Thrown when the target location is not a Margin Folio: there is no root
/// `properties.yaml`, or it is malformed / missing required fields.
class NotAMarginFolioException extends FolioException {
  const NotAMarginFolioException(super.message);
}

/// Thrown when creating a Folio where one already exists.
class FolioExistsException extends FolioException {
  const FolioExistsException(super.message);
}

/// Thrown when a Folio's schema version is newer than this build supports,
/// so it should not be opened (it may have been created by a newer app).
class IncompatibleSchemaException extends FolioException {
  final int found;
  final int supported;

  IncompatibleSchemaException(this.found, this.supported)
      : super('Folio schema version $found is newer than the '
            'supported version $supported');
}
