// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Returns a stable content fingerprint (SHA-256, hex) for [bytes].
///
/// Sync compares these fingerprints across local, remote and last-synced
/// snapshots to decide what to push, pull, or flag as a conflict. A future
/// optimization may skip hashing using size/mtime or a backend ETag, but the
/// content hash is the source of truth.
String contentHash(Uint8List bytes) => sha256.convert(bytes).toString();
