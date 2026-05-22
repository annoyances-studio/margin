// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:yaml/yaml.dart';

import 'endpoint.dart';
import 'yaml_format.dart';

/// The root `properties.yaml`: a repository's identity and the routes by which
/// it can be reached. See DESIGN.md.
///
/// This file is the marker that tells Margin it is dealing with the same
/// repository, regardless of which access route reached it. It never contains
/// credentials.
class RepositoryProperties {
  /// Highest schema version this build understands.
  static const int currentSchemaVersion = 1;

  /// Name of the root properties document, relative to the repository root.
  static const String fileName = 'properties.yaml';

  final int schemaVersion;

  /// Stable repository identifier (a UUID), generated once at creation. Ties
  /// local sync-state and stored credentials to this repository.
  final String id;
  final String name;
  final DateTime created;
  final DateTime updated;

  /// The logical app version that last wrote this file (see [marginAppVersion]).
  final String appVersion;
  final List<Endpoint> endpoints;

  const RepositoryProperties({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    required this.appVersion,
    this.endpoints = const [],
  });

  /// Parses root properties from YAML text.
  ///
  /// Throws [FormatException] if the document is malformed or missing required
  /// fields (`schemaVersion`, `id`).
  factory RepositoryProperties.parse(String yamlText) {
    final dynamic doc = loadYaml(yamlText);
    if (doc is! YamlMap) {
      throw const FormatException('Root properties must be a YAML map');
    }

    final schemaVersion = doc['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException('schemaVersion must be an integer');
    }
    final id = doc['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('id must be a non-empty string');
    }

    final endpoints = <Endpoint>[];
    final rawEndpoints = doc['endpoints'];
    if (rawEndpoints is YamlList) {
      for (final item in rawEndpoints) {
        if (item is YamlMap) {
          endpoints.add(Endpoint.fromMap(item));
        }
      }
    }

    return RepositoryProperties(
      schemaVersion: schemaVersion,
      id: id,
      name: doc['name']?.toString() ?? '',
      created: _parseDate(doc['created']),
      updated: _parseDate(doc['updated']),
      appVersion: doc['appVersion']?.toString() ?? '',
      endpoints: endpoints,
    );
  }

  /// Serializes to YAML text suitable for writing to [fileName].
  String toYaml() {
    final buf = StringBuffer()
      ..writeln('schemaVersion: $schemaVersion')
      ..writeln('id: ${yamlQuote(id)}')
      ..writeln('name: ${yamlQuote(name)}')
      ..writeln('created: ${yamlDate(created)}')
      ..writeln('updated: ${yamlDate(updated)}')
      ..writeln('appVersion: ${yamlQuote(appVersion)}');
    if (endpoints.isEmpty) {
      buf.writeln('endpoints: []');
    } else {
      buf.writeln('endpoints:');
      for (final endpoint in endpoints) {
        buf.writeln('  - type: ${yamlQuote(endpoint.type)}');
        for (final entry in endpoint.properties.entries) {
          buf.writeln('    ${entry.key}: ${yamlQuote(entry.value)}');
        }
      }
    }
    return buf.toString();
  }

  RepositoryProperties copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    DateTime? created,
    DateTime? updated,
    String? appVersion,
    List<Endpoint>? endpoints,
  }) {
    return RepositoryProperties(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      appVersion: appVersion ?? this.appVersion,
      endpoints: endpoints ?? this.endpoints,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Invalid or missing date: $value');
  }
}
