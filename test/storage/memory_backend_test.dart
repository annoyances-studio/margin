// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  late MemoryBackend backend;

  setUp(() => backend = MemoryBackend());

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('write then read round-trips', () async {
    await backend.write('a/b.md', bytes('hi'));
    expect(utf8.decode(await backend.read('a/b.md')), 'hi');
  });

  test('list returns immediate children with directory synthesis', () async {
    await backend.write('Work/note.md', bytes('n'));
    await backend.write('Work/sub/inner.md', bytes('i'));
    await backend.write('top.md', bytes('t'));

    final root = await backend.list('');
    expect(root.map((e) => e.name).toSet(), {'Work', 'top.md'});
    expect(root.firstWhere((e) => e.name == 'Work').isDirectory, isTrue);

    final work = await backend.list('Work');
    expect(work.map((e) => e.name).toSet(), {'note.md', 'sub'});
  });

  test('exists reflects files and synthesized directories', () async {
    expect(await backend.exists('nope'), isFalse);
    await backend.write('x/y.md', bytes('y'));
    expect(await backend.exists('x'), isTrue);
    expect(await backend.exists('x/y.md'), isTrue);
  });

  test('read missing throws NotFoundException', () {
    expect(() => backend.read('ghost.md'), throwsA(isA<NotFoundException>()));
  });

  test('list missing directory throws NotFoundException', () {
    expect(() => backend.list('nodir'), throwsA(isA<NotFoundException>()));
  });

  test('delete removes a directory subtree', () async {
    await backend.write('d/one.md', bytes('1'));
    await backend.write('d/two.md', bytes('2'));
    await backend.delete('d');
    expect(await backend.exists('d'), isFalse);
  });

  test('rejects parent-traversal paths', () {
    expect(() => backend.write('../escape.md', bytes('x')),
        throwsA(isA<InvalidPathException>()));
  });
}
