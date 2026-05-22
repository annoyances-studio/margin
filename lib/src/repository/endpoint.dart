// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// An alternate route to the same repository data (DESIGN.md).
///
/// Endpoints are discovered after first connection and offered as a fallback or
/// convenience (for example a faster LAN SMB path found after first connecting
/// over WebDAV). They never contain credentials — those live in the OS
/// keystore, keyed by the repository id.
///
/// [type] selects the backend (e.g. `webdav`, `smb`, `sftp`); [properties]
/// holds type-specific addressing such as a URL or UNC path.
class Endpoint {
  final String type;
  final Map<String, String> properties;

  const Endpoint({required this.type, this.properties = const {}});

  /// Builds an [Endpoint] from a parsed YAML map. The `type` key is required;
  /// all other keys become string-valued [properties].
  factory Endpoint.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('Endpoint is missing a non-empty "type"');
    }
    final props = <String, String>{};
    for (final entry in map.entries) {
      if (entry.key == 'type') continue;
      props[entry.key.toString()] = entry.value.toString();
    }
    return Endpoint(type: type, properties: props);
  }

  bool _sameProperties(Map<String, String> other) {
    if (other.length != properties.length) return false;
    for (final entry in properties.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is Endpoint &&
      other.type == type &&
      _sameProperties(other.properties);

  @override
  int get hashCode {
    // Order-independent hash over the property entries.
    var propsHash = 0;
    for (final entry in properties.entries) {
      propsHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(type, propsHash);
  }

  @override
  String toString() => 'Endpoint($type, $properties)';
}
