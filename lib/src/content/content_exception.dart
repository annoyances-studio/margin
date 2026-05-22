// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Thrown when a content operation violates a repository rule — for example
/// creating a note at the root (folder-enforced structure), using an invalid
/// name, or creating something that already exists.
class ContentException implements Exception {
  final String message;

  const ContentException(this.message);

  @override
  String toString() => 'ContentException: $message';
}
