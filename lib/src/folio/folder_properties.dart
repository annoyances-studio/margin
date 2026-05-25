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

  /// Optional accent color as a `#RRGGBB` hex string, for a visual cue in the
  /// tree. `null` means no color.
  final String? color;

  const FolderProperties({
    required this.title,
    required this.created,
    this.color,
  });

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
      color: doc['color']?.toString(),
    );
  }

  /// Serializes to YAML text suitable for writing to [fileName].
  String toYaml() {
    final buf = StringBuffer()
      ..writeln('title: ${yamlQuote(title)}')
      ..writeln('created: ${yamlDate(created)}');
    if (color != null) {
      buf.writeln('color: ${yamlQuote(color!)}');
    }
    return buf.toString();
  }

  /// Returns a copy with the given fields replaced. Pass [clearColor] to remove
  /// the color (since passing `color: null` cannot be distinguished from "leave
  /// unchanged").
  FolderProperties copyWith({
    String? title,
    DateTime? created,
    String? color,
    bool clearColor = false,
  }) {
    return FolderProperties(
      title: title ?? this.title,
      created: created ?? this.created,
      color: clearColor ? null : (color ?? this.color),
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
