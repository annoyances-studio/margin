// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/content/markdown_convert.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/clipboard_service.dart';

/// In-memory clipboard for tests.
class _FakeClipboard implements ClipboardService {
  String? html;
  String? text;

  @override
  Future<void> copyText(String t) async {
    text = t;
    html = null;
  }

  @override
  Future<void> copyRich({required String html, required String text}) async {
    this.html = html;
    this.text = text;
  }

  @override
  Future<String?> readHtml() async => html;
  @override
  Future<String?> readText() async => text;
  @override
  Future<ClipboardImage?> readImage() async => null;
}

void main() {
  Future<AppController> openWith(String body, _FakeClipboard clip) async {
    final c = AppController(clipboard: clip);
    addTearDown(c.dispose);
    await c.create(MemoryBackend(), 'Notes');
    await c.createFolder('Work');
    await c.createNote('n', folderPath: 'Work');
    c.updateBody(body);
    return c;
  }

  group('copy', () {
    test('copyNoteFormatted writes HTML + a plain-text fallback', () async {
      final clip = _FakeClipboard();
      final c = await openWith('# Title\n\nSome **bold** text', clip);

      await c.copyNoteFormatted();

      expect(clip.html, contains('<h1>Title</h1>'));
      expect(clip.html, contains('<strong>bold</strong>'));
      expect(clip.text, contains('Some bold text')); // fallback, no markup
      expect(clip.text, isNot(contains('**')));
    });

    test('copyNoteMarkdown writes the raw source', () async {
      final clip = _FakeClipboard();
      final c = await openWith('# Title\n\n**bold**', clip);

      await c.copyNoteMarkdown();

      expect(clip.text, '# Title\n\n**bold**');
      expect(clip.html, isNull);
    });

    test('copyNotePlain strips the markup', () async {
      final clip = _FakeClipboard();
      final c = await openWith('# Title\n\n**bold**', clip);

      await c.copyNotePlain();

      expect(clip.text, contains('Title'));
      expect(clip.text, contains('bold'));
      expect(clip.text, isNot(contains('#')));
      expect(clip.text, isNot(contains('**')));
    });

    test('copy is a no-op with no open note', () async {
      final clip = _FakeClipboard();
      final c = AppController(clipboard: clip);
      addTearDown(c.dispose);
      expect(c.canCopyNote, isFalse);
      await c.copyNoteMarkdown();
      expect(clip.text, isNull);
    });
  });

  group('images', () {
    test('copyNoteFormatted inlines a local attachment image as base64',
        () async {
      final tmp = await Directory.systemTemp.createTemp('margin_copyimg_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final backend = LocalFolderBackend(tmp.path);
      final clip = _FakeClipboard();
      final c = AppController(clipboard: clip);
      addTearDown(c.dispose);
      await c.create(backend, 'N');
      await c.createFolder('W');
      await c.createNote('n', folderPath: 'W');
      await backend.write(
          'W/_attachments/pic.png', Uint8List.fromList([1, 2, 3, 4]));
      c.updateBody('![](_attachments/pic.png)');

      await c.copyNoteFormatted();

      expect(clip.html, contains('data:image/png;base64,'));
      expect(clip.html, isNot(contains('src="_attachments/pic.png"')));
    });

    test('saveAttachmentForCurrentNote writes bytes and returns the link',
        () async {
      final tmp = await Directory.systemTemp.createTemp('margin_saveatt_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final backend = LocalFolderBackend(tmp.path);
      final c = AppController();
      addTearDown(c.dispose);
      await c.create(backend, 'N');
      await c.createFolder('W');
      await c.createNote('n', folderPath: 'W');

      final link = await c.saveAttachmentForCurrentNote(
          Uint8List.fromList([9, 8, 7]), 'png');

      expect(link, startsWith('_attachments/'));
      expect(await backend.exists('W/$link'), isTrue);
    });

    test('downloadImageAsAttachment fetches a remote image and saves it',
        () async {
      final tmp = await Directory.systemTemp.createTemp('margin_dl_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final backend = LocalFolderBackend(tmp.path);
      final mock = MockClient((req) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'image/jpeg'},
          ));
      final c = AppController(httpClientFactory: () => mock);
      addTearDown(c.dispose);
      await c.create(backend, 'N');
      await c.createFolder('W');
      await c.createNote('n', folderPath: 'W');

      final link = await c.downloadImageAsAttachment('https://i.test/pic.jpg');

      expect(link, startsWith('_attachments/'));
      expect(link, endsWith('.jpg')); // from image/jpeg content-type
      expect(await backend.exists('W/$link'), isTrue);
    });

    test('downloadImageAsAttachment returns null on a non-200', () async {
      final c = AppController(
        httpClientFactory: () => MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(c.dispose);
      expect(
        await c.downloadImageAsAttachment('https://i.test/missing.png'),
        isNull,
      );
    });
  });

  group('clipboardToMarkdown (paste decision)', () {
    test('converts HTML to Markdown when present', () {
      final md = clipboardToMarkdown(
        html: '<h2>Heading</h2><p>a <em>word</em></p>',
        plainText: 'Heading a word',
      );
      expect(md, contains('## Heading'));
      expect(md, contains('*word*'));
    });

    test('falls back to plain text when there is no HTML', () {
      expect(clipboardToMarkdown(html: null, plainText: 'just text'), 'just text');
      expect(clipboardToMarkdown(html: '   ', plainText: 'just text'), 'just text');
    });

    test('empty when nothing is on the clipboard', () {
      expect(clipboardToMarkdown(html: null, plainText: null), isEmpty);
    });
  });
}
