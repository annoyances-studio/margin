// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  group('Note', () {
    test('parses frontmatter and body', () {
      const content = '---\n'
          'title: "Meeting notes"\n'
          'tags:\n'
          '  - work\n'
          '  - q2\n'
          '---\n'
          '# Heading\n\nbody text';
      final note = Note.parse(content);

      expect(note.frontmatter.title, 'Meeting notes');
      expect(note.frontmatter.tags, ['work', 'q2']);
      expect(note.body, '# Heading\n\nbody text');
    });

    test('treats content without frontmatter as pure body', () {
      const content = '# Just markdown\n\nno frontmatter here';
      final note = Note.parse(content);

      expect(note.frontmatter.title, '');
      expect(note.frontmatter.tags, isEmpty);
      expect(note.body, content);
    });

    test('round-trips through serialize/parse', () {
      final note = Note(
        frontmatter: NoteFrontmatter(
          title: 'Tricky: "title" \\ 🗒️',
          created: DateTime.utc(2026, 5, 22, 10),
          updated: DateTime.utc(2026, 5, 22, 14, 30),
          tags: const ['a', 'b'],
        ),
        body: '## Body\n\n- [ ] task\n',
      );

      final parsed = Note.parse(note.serialize());
      expect(parsed.frontmatter.title, note.frontmatter.title);
      expect(parsed.frontmatter.created, note.frontmatter.created);
      expect(parsed.frontmatter.updated, note.frontmatter.updated);
      expect(parsed.frontmatter.tags, note.frontmatter.tags);
      expect(parsed.body, note.body);
    });

    test('normalizes CRLF to LF on parse', () {
      const content = '---\r\ntitle: "x"\r\n---\r\nline1\r\nline2';
      final note = Note.parse(content);
      expect(note.frontmatter.title, 'x');
      expect(note.body, 'line1\nline2');
    });

    test('serializes empty tags as an empty list', () {
      final note = Note(
        frontmatter: const NoteFrontmatter(title: 'x'),
        body: 'b',
      );
      expect(note.serialize(), contains('tags: []'));
    });
  });
}
