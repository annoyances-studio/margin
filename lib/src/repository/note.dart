// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:yaml/yaml.dart';

import 'yaml_format.dart';

/// Metadata stored as YAML frontmatter at the top of a note's `.md` file.
///
/// All fields are optional so that Markdown files created or edited by other
/// tools (which may have no frontmatter) still load. Margin always writes at
/// least a title.
class NoteFrontmatter {
  final String title;
  final DateTime? created;
  final DateTime? updated;
  final List<String> tags;

  const NoteFrontmatter({
    this.title = '',
    this.created,
    this.updated,
    this.tags = const [],
  });

  /// Builds frontmatter from a parsed YAML value. A non-map (or null) yields
  /// empty frontmatter.
  factory NoteFrontmatter.fromYaml(dynamic yaml) {
    if (yaml is! YamlMap) return const NoteFrontmatter();
    final rawTags = yaml['tags'];
    return NoteFrontmatter(
      title: yaml['title']?.toString() ?? '',
      created: _parseDate(yaml['created']),
      updated: _parseDate(yaml['updated']),
      tags: rawTags is YamlList
          ? rawTags.map((e) => e.toString()).toList(growable: false)
          : const [],
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// A note: its frontmatter plus the Markdown body that follows it.
///
/// The body never includes the frontmatter delimiters. Line endings are
/// normalized to `\n` on parse.
class Note {
  final NoteFrontmatter frontmatter;
  final String body;

  const Note({required this.frontmatter, required this.body});

  /// Parses note [content] into frontmatter and body.
  ///
  /// Recognizes a leading frontmatter block delimited by `---` lines. If no
  /// frontmatter is present, the entire content becomes the [body] with empty
  /// frontmatter.
  factory Note.parse(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    if (normalized.startsWith('---\n')) {
      // Find the closing delimiter: a line containing only '---'.
      final close = RegExp(r'\n---[ \t]*(?:\n|$)').firstMatch(normalized);
      if (close != null && close.start >= 4) {
        final yamlText = normalized.substring(4, close.start);
        final body = normalized.substring(close.end);
        return Note(
          frontmatter: NoteFrontmatter.fromYaml(loadYaml(yamlText)),
          body: body,
        );
      }
    }
    return Note(frontmatter: const NoteFrontmatter(), body: normalized);
  }

  /// Serializes the note to text: a frontmatter block followed by the body.
  String serialize() {
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${yamlQuote(frontmatter.title)}');
    if (frontmatter.created != null) {
      buf.writeln('created: ${yamlDate(frontmatter.created!)}');
    }
    if (frontmatter.updated != null) {
      buf.writeln('updated: ${yamlDate(frontmatter.updated!)}');
    }
    if (frontmatter.tags.isEmpty) {
      buf.writeln('tags: []');
    } else {
      buf.writeln('tags:');
      for (final tag in frontmatter.tags) {
        buf.writeln('  - ${yamlQuote(tag)}');
      }
    }
    buf.writeln('---');
    buf.write(body);
    return buf.toString();
  }
}
