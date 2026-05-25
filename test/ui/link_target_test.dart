// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/link_target.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isExternalUrl', () {
    test('http(s)/mailto are external', () {
      expect(isExternalUrl('https://example.com'), isTrue);
      expect(isExternalUrl('http://example.com'), isTrue);
      expect(isExternalUrl('mailto:a@b.c'), isTrue);
    });

    test('relative paths and file: are not external', () {
      expect(isExternalUrl('pics/a.png'), isFalse);
      expect(isExternalUrl('../notes/b.md'), isFalse);
      expect(isExternalUrl('file:///tmp/x'), isFalse);
    });
  });

  group('isImageTarget', () {
    test('recognises image extensions regardless of case', () {
      expect(isImageTarget('a.PNG'), isTrue);
      expect(isImageTarget('dir/b.jpeg'), isTrue);
      expect(isImageTarget('c.webp'), isTrue);
    });

    test('rejects non-image extensions', () {
      expect(isImageTarget('notes.md'), isFalse);
      expect(isImageTarget('archive.zip'), isFalse);
      expect(isImageTarget('https://x.y/page'), isFalse);
    });
  });

  group('resolveLinkTarget', () {
    test('returns external URLs unchanged', () {
      expect(
        resolveLinkTarget('https://example.com/p', '/base'),
        'https://example.com/p',
      );
    });

    test('joins relative links against the base dir', () {
      final result = resolveLinkTarget('pics/a.png', '/repo/Work');
      expect(result, p.normalize('/repo/Work/pics/a.png'));
    });

    test('decodes percent-encoded relative paths', () {
      final result = resolveLinkTarget('pics/a%20b.png', '/repo');
      expect(result, p.normalize('/repo/pics/a b.png'));
    });

    test('does not throw on raw non-ASCII names (the grey-box regression)', () {
      // Uri.decodeFull throws ArgumentError on raw multi-byte names; the
      // resolver must fall back to the literal href instead of crashing.
      final result =
          resolveLinkTarget('_attachments/長い名前のファイル.png', '/repo/Work');
      expect(result, p.normalize('/repo/Work/_attachments/長い名前のファイル.png'));
    });

    test('falls back on malformed percent-encoding without throwing', () {
      final result = resolveLinkTarget('pics/a%2.png', '/repo');
      expect(result, p.normalize('/repo/pics/a%2.png'));
    });

    test('returns null for empty href or missing base', () {
      expect(resolveLinkTarget('', '/base'), isNull);
      expect(resolveLinkTarget('pics/a.png', null), isNull);
    });
  });
}
