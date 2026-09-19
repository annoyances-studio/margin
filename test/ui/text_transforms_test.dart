// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/text_transforms.dart';

void main() {
  group('applyTextTool', () {
    test('case: upper / lower / proper', () {
      expect(applyTextTool('upper', 'aB c'), 'AB C');
      expect(applyTextTool('lower', 'aB C'), 'ab c');
      expect(
        applyTextTool('proper', 'hello WORLD\nfoo bar'),
        'Hello World\nFoo Bar',
      );
    });

    test('lines: sort (case-insensitive) and remove empty', () {
      expect(
        applyTextTool('sort', 'banana\nApple\ncherry'),
        'Apple\nbanana\ncherry',
      );
      expect(applyTextTool('noEmpty', 'a\n\n  \nb'), 'a\nb');
    });

    test('whitespace: trim trailing and tabs to spaces', () {
      expect(applyTextTool('trim', 'a  \nb\t \nc'), 'a\nb\nc');
      expect(applyTextTool('tabs', 'a\tb'), 'a  b');
    });

    test('unknown action is a no-op', () {
      expect(applyTextTool('nope', 'x'), 'x');
    });
  });
}
