// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:yaml/yaml.dart';

import 'yaml_format.dart';

/// Per-note metadata, stored in a sidecar `<note>.md.yaml` next to the note
/// (DESIGN.md). Kept separate from the note's content so UI preferences don't
/// alter the `.md` (or its modified time). Room to grow (color, icon, ...).
class NoteProperties {
  /// Stored view id (`editor` / `split` / `preview`), or null.
  final String? view;

  const NoteProperties({this.view});

  bool get isEmpty => view == null;

  factory NoteProperties.parse(String yamlText) {
    final dynamic doc = loadYaml(yamlText);
    if (doc is! YamlMap) return const NoteProperties();
    return NoteProperties(view: doc['view']?.toString());
  }

  String toYaml() {
    final buf = StringBuffer();
    if (view != null) buf.writeln('view: ${yamlQuote(view!)}');
    return buf.toString();
  }

  NoteProperties copyWith({String? view}) =>
      NoteProperties(view: view ?? this.view);
}
