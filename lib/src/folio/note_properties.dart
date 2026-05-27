// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:yaml/yaml.dart';

import 'yaml_format.dart';

/// Per-note metadata, stored in a sidecar `<note>.md.yaml` next to the note
/// (DESIGN.md).
///
/// Two roles:
/// - A lightweight **search index**: [title], [tags] and [updated] mirror the
///   note's frontmatter so search can scan these tiny files instead of opening
///   (and decoding) every `.md`. They are rewritten whenever the note is saved.
/// - A small bag of **UI preferences**: [view] (the per-note editor/split/
///   preview choice). Kept out of the `.md` so toggling it doesn't alter the
///   note or its modified time.
class NoteProperties {
  /// Note title (mirrors the `.md` frontmatter) — indexed for search.
  final String? title;

  /// Tags (mirror the frontmatter) — indexed for search.
  final List<String> tags;

  /// Last-modified time (mirrors the frontmatter) — for index sort/filter.
  final DateTime? updated;

  /// Stored view id (`editor` / `split` / `preview`), or null.
  final String? view;

  const NoteProperties({
    this.title,
    this.tags = const [],
    this.updated,
    this.view,
  });

  bool get isEmpty =>
      title == null && tags.isEmpty && updated == null && view == null;

  factory NoteProperties.parse(String yamlText) {
    final dynamic doc = loadYaml(yamlText);
    if (doc is! YamlMap) return const NoteProperties();
    final rawTags = doc['tags'];
    return NoteProperties(
      title: doc['title']?.toString(),
      tags: rawTags is YamlList
          ? rawTags.map((e) => e.toString()).toList(growable: false)
          : const [],
      updated: _parseDate(doc['updated']),
      view: doc['view']?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String toYaml() {
    final buf = StringBuffer();
    if (title != null) buf.writeln('title: ${yamlQuote(title!)}');
    if (tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in tags) {
        buf.writeln('  - ${yamlQuote(tag)}');
      }
    }
    if (updated != null) buf.writeln('updated: ${yamlDate(updated!)}');
    if (view != null) buf.writeln('view: ${yamlQuote(view!)}');
    return buf.toString();
  }

  NoteProperties copyWith({
    String? title,
    List<String>? tags,
    DateTime? updated,
    String? view,
  }) =>
      NoteProperties(
        title: title ?? this.title,
        tags: tags ?? this.tags,
        updated: updated ?? this.updated,
        view: view ?? this.view,
      );
}
