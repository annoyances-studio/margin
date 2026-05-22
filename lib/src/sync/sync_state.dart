// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// A per-device record of the last successfully synced state: a map of
/// repository-relative path to content hash at that moment (DESIGN.md).
///
/// This is the "base" of the three-way comparison. It is local to each device
/// and must NOT be synced into the repository — it lives in the app's support
/// directory, keyed by the repository id.
class SyncState {
  /// Schema version of the persisted form, for future migrations.
  static const int currentVersion = 1;

  final Map<String, String> hashes;

  const SyncState(this.hashes);

  const SyncState.empty() : hashes = const {};

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'hashes': hashes,
      };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final rawHashes = json['hashes'];
    if (rawHashes is! Map) return const SyncState.empty();
    return SyncState(rawHashes.map((k, v) => MapEntry('$k', '$v')));
  }

  /// Serializes to a JSON string for persistence.
  String encode() => jsonEncode(toJson());

  /// Parses a JSON string previously produced by [encode].
  factory SyncState.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) return const SyncState.empty();
    return SyncState.fromJson(decoded);
  }
}
