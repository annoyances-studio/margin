// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

/// Transforms note bytes between their in-app form and their at-rest form on a
/// [StorageBackend].
///
/// This is the seam where encryption will later slot in (DESIGN.md). The
/// default [IdentityCodec] is a passthrough, so higher layers can be written
/// against this interface today with no behavioural change, and an encrypting
/// codec can be added later without touching the sync engine or backends.
abstract interface class ContentCodec {
  /// Transforms in-app bytes into the form stored on the backend.
  Uint8List encode(Uint8List plain);

  /// Transforms stored bytes back into in-app bytes.
  Uint8List decode(Uint8List stored);
}

/// A no-op [ContentCodec]: stored bytes are identical to in-app bytes.
///
/// This is the default for plaintext repositories.
class IdentityCodec implements ContentCodec {
  const IdentityCodec();

  @override
  Uint8List encode(Uint8List plain) => plain;

  @override
  Uint8List decode(Uint8List stored) => stored;
}
