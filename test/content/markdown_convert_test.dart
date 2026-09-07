// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

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

  group('rewriteDataUriImages', () {
    test('saves data-URI images as attachments labelled [Pasted Image]',
        () async {
      final exts = <String>[];
      final out = await rewriteDataUriImages(
        'before ![](data:image/png;base64,aW1n) after',
        (bytes, ext) async {
          exts.add(ext);
          return '_attachments/pasted.$ext';
        },
      );
      expect(exts, ['png']);
      expect(out, 'before ![Pasted Image](_attachments/pasted.png) after');
    });

    test('maps jpeg to a jpg extension', () async {
      String? ext;
      await rewriteDataUriImages('![](data:image/jpeg;base64,aW1n)',
          (bytes, e) async {
        ext = e;
        return '_attachments/x.$e';
      });
      expect(ext, 'jpg');
    });

    test('leaves regular image links untouched', () async {
      const md = '![alt](pics/photo.png)';
      final out = await rewriteDataUriImages(md, (b, e) async => 'nope');
      expect(out, md);
    });

    test('keeps the embed when the save fails (returns null)', () async {
      const md = '![](data:image/png;base64,aW1n)';
      final out = await rewriteDataUriImages(md, (b, e) async => null);
      expect(out, md);
    });

    test('handles a multi-megabyte payload without a StackOverflowError',
        () async {
      // Regression: a pasted screenshot arrives as a huge base64 data URI. The
      // old capturing regex recursed over it and threw StackOverflowError,
      // silently killing the whole paste. A valid ~4 MB base64 blob (bytes are
      // "A" repeated; length a multiple of 3 so there's no padding).
      final big = base64.encode(Uint8List(3 * 1000 * 1000));
      var saved = 0;
      final out = await rewriteDataUriImages(
        '![shot](data:image/png;base64,$big)',
        (bytes, ext) async {
          saved++;
          return '_attachments/pasted.$ext';
        },
      );
      expect(saved, 1);
      expect(out, '![Pasted Image](_attachments/pasted.png)');
    });

    test('rewrites a linked data-URI image, keeping the outer link', () async {
      final out = await rewriteDataUriImages(
        '[![alt](data:image/png;base64,aW1n)](https://example.com/x)',
        (bytes, ext) async => '_attachments/pasted.$ext',
      );
      expect(out,
          '[![Pasted Image](_attachments/pasted.png)](https://example.com/x)');
    });
  });

  group('embedHtmlImages', () {
    test('inlines a local image as a base64 data URI', () async {
      final out = await embedHtmlImages(
        '<p><img src="pic.png" alt="x"></p>',
        (src) async => Uint8List.fromList([1, 2, 3]),
      );
      expect(out, contains('data:image/png;base64,'));
      expect(out, isNot(contains('src="pic.png"')));
    });

    test('leaves http and data sources alone', () async {
      const html =
          '<img src="https://x.test/y.png"><img src="data:image/png;base64,aW1n">';
      final out = await embedHtmlImages(html, (src) async => fail('read $src'));
      expect(out, html);
    });

    test('keeps the tag when the image cannot be read', () async {
      const html = '<img src="missing.png">';
      final out = await embedHtmlImages(html, (src) async => null);
      expect(out, html);
    });
  });

  group('rewriteRemoteImages', () {
    test('hasRemoteImages detects http(s) image embeds', () {
      expect(hasRemoteImages('![](https://x.test/a.png)'), isTrue);
      expect(hasRemoteImages('![](_attachments/a.png)'), isFalse);
      expect(hasRemoteImages('no images here'), isFalse);
    });

    test('downloads remote images and re-links to the attachment', () async {
      final urls = <String>[];
      final out = await rewriteRemoteImages(
        'see ![](https://i.test/vi/abc/hq.jpg?x=1) here',
        (url) async {
          urls.add(url);
          return '_attachments/dl.jpg';
        },
      );
      expect(urls, ['https://i.test/vi/abc/hq.jpg?x=1']);
      expect(out, 'see ![Pasted Image](_attachments/dl.jpg) here');
    });

    test('preserves a non-empty alt label', () async {
      final out = await rewriteRemoteImages(
        '![a cat](https://x.test/cat.png)',
        (url) async => '_attachments/cat.png',
      );
      expect(out, '![a cat](_attachments/cat.png)');
    });

    test('keeps the hotlink when the download fails', () async {
      const md = '![](https://x.test/dead.png)';
      final out = await rewriteRemoteImages(md, (url) async => null);
      expect(out, md);
    });
  });
}
