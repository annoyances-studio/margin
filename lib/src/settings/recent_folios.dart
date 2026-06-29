// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// How many recent Folios the app remembers — in practice a "quick Folio
/// switch" list on the landing screen.
const int kMaxRecentFolios = 8;

/// A remembered way back into a Folio — everything needed to reconnect
/// *except* secrets (WebDAV passwords and OAuth tokens stay in the OS
/// keystore; reconnect reads them from there).
///
/// The device-notes Folio is never recorded: it has its own permanent landing
/// button.
class RecentFolio {
  /// Backend type id: `local`, `webdav`, or `onedrive`.
  final String type;

  /// Where the Folio lives: a filesystem path (`local`), the collection base
  /// URL (`webdav`), or the drive-root-relative folder path (`onedrive`).
  final String location;

  /// The Folio's display name (from its `properties.yaml`).
  final String name;

  /// WebDAV username (non-secret); null for other types.
  final String? user;

  /// The remote Folio's id (UUID) so its on-device cache can be adopted
  /// offline-first; null for local Folios.
  final String? id;

  const RecentFolio({
    required this.type,
    required this.location,
    required this.name,
    this.user,
    this.id,
  });

  /// Two entries point at the same Folio when type and location match.
  bool sameTarget(RecentFolio other) =>
      type == other.type && location == other.location;

  Map<String, dynamic> toJson() => {
        'type': type,
        'location': location,
        'name': name,
        if (user != null) 'user': user,
        if (id != null) 'id': id,
      };

  static RecentFolio? fromJson(dynamic json) {
    if (json is! Map) return null;
    final type = json['type'];
    final location = json['location'];
    if (type is! String || location is! String) return null;
    return RecentFolio(
      type: type,
      location: location,
      name: json['name'] is String ? json['name'] as String : location,
      user: json['user'] is String ? json['user'] as String : null,
      id: json['id'] is String ? json['id'] as String : null,
    );
  }
}

/// Decodes the persisted JSON list; tolerant of garbage (returns empty).
List<RecentFolio> decodeRecentFolios(String? source) {
  if (source == null || source.isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .map(RecentFolio.fromJson)
        .whereType<RecentFolio>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeRecentFolios(List<RecentFolio> folios) =>
    jsonEncode(folios.map((f) => f.toJson()).toList(growable: false));

/// Returns a new list with [entry] at the front, any earlier entry for the
/// same target removed, and the result capped at [cap].
List<RecentFolio> upsertRecentFolio(
  List<RecentFolio> folios,
  RecentFolio entry, {
  int cap = kMaxRecentFolios,
}) {
  final rest = folios.where((f) => !f.sameTarget(entry));
  return [entry, ...rest].take(cap).toList(growable: false);
}
