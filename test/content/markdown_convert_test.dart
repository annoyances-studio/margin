// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/content/markdown_convert.dart';

void main() {
  group('markdownToHtml', () {
    test('renders headings, bold, and lists', () {
      final html = markdownToHtml('# Title\n\nSome **bold** text\n\n- a\n- b');
      expect(html, contains('<h1>Title</h1>'));
      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains('<li>a</li>'));
    });

    test('handles GitHub tables (gfm extension)', () {
      final html = markdownToHtml('| A | B |\n|---|---|\n| 1 | 2 |');
      expect(html, contains('<table>'));
      expect(html, contains('<td>1</td>'));
    });
  });

  group('htmlToMarkdown', () {
    test('converts headings, bold, and lists back to Markdown', () {
      final md = htmlToMarkdown(
        '<h1>Title</h1><p>Some <strong>bold</strong> text</p>'
        '<ul><li>a</li><li>b</li></ul>',
      );
      expect(md, contains('# Title'));
      expect(md, contains('**bold**'));
      expect(md, matches(RegExp(r'-\s+a'))); // dash bullet, spacing-tolerant
    });

    test('a round-trip preserves the essentials', () {
      const original = '# Hello\n\nA **bold** idea and a [link](https://x.test).';
      final back = htmlToMarkdown(markdownToHtml(original));
      expect(back, contains('# Hello'));
      expect(back, contains('**bold**'));
      expect(back, contains('[link](https://x.test)'));
    });
  });

  group('markdownToPlainText', () {
    test('strips markup but keeps the words and line breaks', () {
      final text = markdownToPlainText('# Title\n\nSome **bold** text');
      expect(text, contains('Title'));
      expect(text, contains('Some bold text'));
      expect(text, isNot(contains('#')));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('<')));
    });

    test('decodes basic entities', () {
      final text = markdownToPlainText('Tom & Jerry < Co');
      expect(text, contains('Tom & Jerry'));
      expect(text, isNot(contains('&amp;')));
    });
  });
}
