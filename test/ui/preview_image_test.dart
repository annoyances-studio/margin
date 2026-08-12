// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

import '../support/test_app.dart';

void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('AppController.readNoteImage', () {
    Future<AppController> browseWith(MemoryBackend backend) async {
      final controller = AppController();
      addTearDown(controller.dispose);
      await controller.open(backend); // no properties.yaml -> browse mode
      return controller;
    }

    test('reads an image relative to the open note, through the backend',
        () async {
      final backend = MemoryBackend();
      await backend.write('Work/note.md', bytes('# n'));
      await backend.write('Work/_attachments/pic.png', bytes('IMGBYTES'));
      final controller = await browseWith(backend);
      await controller.selectNote(
          const NoteNode(path: 'Work/note.md', name: 'note.md'));

      final data = await controller.readNoteImage('_attachments/pic.png');
      expect(data, isNotNull);
      expect(utf8.decode(data!), 'IMGBYTES');
    });

    test('returns null for remote srcs and for paths escaping the root',
        () async {
      final backend = MemoryBackend();
      await backend.write('Work/note.md', bytes('# n'));
      final controller = await browseWith(backend);
      await controller.selectNote(
          const NoteNode(path: 'Work/note.md', name: 'note.md'));

      expect(await controller.readNoteImage('https://x.y/z.png'), isNull);
      expect(await controller.readNoteImage('../../secret.png'), isNull);
      expect(await controller.readNoteImage('missing.png'), isNull);
    });
  });

  testWidgets('preview renders a backend image when there is no local file',
      (tester) async {
    // A valid 1x1 transparent PNG.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
        '2mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    var asked = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownPreview(
          data: '![alt](pic.png)',
          imageBaseDir: null, // no file on disk -> the loader path
          imageLoader: (src) async {
            asked.add(src);
            return png;
          },
        ),
      ),
    ));
    await tester.pump(); // let the loader future resolve
    await tester.pump();

    expect(asked, contains('pic.png'));
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  group('Git LFS pointer', () {
    Uint8List pointer() => bytes(
        'version https://git-lfs.github.com/spec/v1\n'
        'oid sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nsize 12345\n');

    test('isLfsPointer detects a stub and rejects real content', () {
      expect(isLfsPointer(pointer()), isTrue);
      expect(isLfsPointer(bytes('just some text')), isFalse);
      expect(isLfsPointer(Uint8List(0)), isFalse);
      // Too big to be a pointer, even if it happened to start right.
      expect(isLfsPointer(Uint8List(2000)), isFalse);
    });

    testWidgets('preview shows an actionable hint, not a broken image',
        (tester) async {
      await tester.pumpWidget(localizedApp(Scaffold(
        body: MarkdownPreview(
          data: '![alt](big.png)',
          imageBaseDir: null,
          imageLoader: (_) async => pointer(),
        ),
      )));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('git lfs pull'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  });
}
