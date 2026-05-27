// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/folio/note_properties.dart';

void main() {
  test('round-trips the index fields and view through YAML', () {
    final props = NoteProperties(
      title: 'My Note',
      tags: const ['work', 'urgent'],
      updated: DateTime.utc(2026, 1, 2, 3, 4, 5),
      view: 'preview',
    );

    final parsed = NoteProperties.parse(props.toYaml());
    expect(parsed.title, 'My Note');
    expect(parsed.tags, ['work', 'urgent']);
    expect(parsed.updated, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(parsed.view, 'preview');
  });

  test('empty when no field is set; non-empty once any is', () {
    expect(const NoteProperties().isEmpty, isTrue);
    expect(const NoteProperties(title: 'x').isEmpty, isFalse);
    expect(const NoteProperties(view: 'split').isEmpty, isFalse);
    expect(const NoteProperties(tags: ['a']).isEmpty, isFalse);
  });

  test('parse tolerates a missing/blank/non-map sidecar', () {
    expect(NoteProperties.parse('').isEmpty, isTrue);
    expect(NoteProperties.parse('just a string').isEmpty, isTrue);
  });

  test('copyWith preserves the other fields', () {
    const base = NoteProperties(title: 'T', tags: ['a'], view: 'editor');
    final updated = base.copyWith(view: 'preview');
    expect(updated.title, 'T');
    expect(updated.tags, ['a']);
    expect(updated.view, 'preview');
  });
}
