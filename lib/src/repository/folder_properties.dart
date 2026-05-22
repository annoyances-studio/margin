// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:yaml/yaml.dart';

import 'yaml_format.dart';

/// The per-directory `properties.yaml`: metadata about the notes in a folder.
/// See DESIGN.md.
class FolderProperties {
  /// Name of the folder properties document, relative to the folder.
  static const String fileName = 'properties.yaml';

  final String title;
  final DateTime created;

  const FolderProperties({required this.title, required this.created});

  /// Parses folder properties from YAML text.
  ///
  /// Throws [FormatException] if the document is malformed.
  factory FolderProperties.parse(String yamlText) {
    final dynamic doc = loadYaml(yamlText);
    if (doc is! YamlMap) {
      throw const FormatException('Folder properties must be a YAML map');
    }
    return FolderProperties(
      title: doc['title']?.toString() ?? '',
      created: _parseDate(doc['created']),
    );
  }

  /// Serializes to YAML text suitable for writing to [fileName].
  String toYaml() {
    final buf = StringBuffer()
      ..writeln('title: ${yamlQuote(title)}')
      ..writeln('created: ${yamlDate(created)}');
    return buf.toString();
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
