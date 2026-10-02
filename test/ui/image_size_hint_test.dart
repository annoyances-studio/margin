// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

void main() {
  group('imageSizeFromAlt', () {
    test('parses a width-only hint', () {
      final s = imageSizeFromAlt('diagram|300');
      expect(s.width, 300);
      expect(s.height, isNull);
    });

    test('parses a width x height hint', () {
      final s = imageSizeFromAlt('shot|300x200');
      expect(s.width, 300);
      expect(s.height, 200);
    });

    test('uses the last bar so alt text may contain pipes', () {
      expect(imageSizeFromAlt('a | b | 120').width, 120);
    });

    test('ignores non-numeric or absent hints', () {
      expect(imageSizeFromAlt('just alt text').width, isNull);
      expect(imageSizeFromAlt('alt|big').width, isNull);
      expect(imageSizeFromAlt('alt|').width, isNull);
      expect(imageSizeFromAlt(null).width, isNull);
      expect(imageSizeFromAlt('').width, isNull);
    });

    test('tolerates surrounding spaces in the hint', () {
      final s = imageSizeFromAlt('alt| 640x480 ');
      expect(s.width, 640);
      expect(s.height, 480);
    });
  });
}
