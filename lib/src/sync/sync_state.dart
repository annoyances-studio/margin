// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// One cached fingerprint→hash record: the [fingerprint] a backend reported for
/// a file last time, and the content [hash] we computed for those bytes. If a
/// later listing reports the same fingerprint, the hash can be reused without
/// re-reading (and, for a remote, re-downloading) the file.
typedef FileHash = ({String fingerprint, String hash});

/// A path→[FileHash] map: sync's content-hash cache for one backend.
typedef HashCache = Map<String, FileHash>;

/// A per-device record of the last successfully synced state: a map of
/// repository-relative path to content hash at that moment (DESIGN.md).
///
/// This is the "base" of the three-way comparison. It is local to each device
/// and must NOT be synced into the repository — it lives in the app's support
/// directory, keyed by the repository id.
///
/// It also carries a content-hash cache for each side ([localCache],
/// [remoteCache]): a memo of `fingerprint → content hash` so an unchanged file
/// is not re-read (or re-downloaded) just to recompute a hash it already had.
/// The caches are a pure optimization — the content hash stays canonical — so a
/// missing or stale cache only costs work, never correctness.
class SyncState {
  /// Schema version of the persisted form, for future migrations.
  static const int currentVersion = 2;

  final Map<String, String> hashes;

  /// Content-hash cache for the local backend (see the class doc).
  final HashCache localCache;

  /// Content-hash cache for the remote backend (see the class doc).
  final HashCache remoteCache;

  const SyncState(
    this.hashes, {
    this.localCache = const {},
    this.remoteCache = const {},
  });

  const SyncState.empty()
      : hashes = const {},
        localCache = const {},
        remoteCache = const {};

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'hashes': hashes,
        'localCache': _encodeCache(localCache),
        'remoteCache': _encodeCache(remoteCache),
      };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final rawHashes = json['hashes'];
    if (rawHashes is! Map) return const SyncState.empty();
    return SyncState(
      rawHashes.map((k, v) => MapEntry('$k', '$v')),
      localCache: _decodeCache(json['localCache']),
      remoteCache: _decodeCache(json['remoteCache']),
    );
  }

  /// Serializes to a JSON string for persistence.
  String encode() => jsonEncode(toJson());

  /// Parses a JSON string previously produced by [encode].
  factory SyncState.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) return const SyncState.empty();
    return SyncState.fromJson(decoded);
  }

  static Map<String, dynamic> _encodeCache(HashCache cache) => cache.map(
      (path, fh) => MapEntry(path, {'f': fh.fingerprint, 'h': fh.hash}));

  /// Reads a cache back, tolerating anything malformed (drops that entry): a
  /// bad cache just means a re-hash, so lenient parsing keeps sync working.
  static HashCache _decodeCache(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, FileHash>{};
    raw.forEach((k, v) {
      if (v is Map && v['f'] is String && v['h'] is String) {
        out['$k'] = (fingerprint: v['f'] as String, hash: v['h'] as String);
      }
    });
    return out;
  }
}
