// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/byte_format.dart';

void main() {
  test('formats bytes in binary units, dropping a trailing .0', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(2 * 1024 * 1024), '2 MB');
    expect(formatBytes((3.4 * 1024 * 1024).round()), '3.4 MB');
    expect(formatBytes(2 * 1024 * 1024 * 1024), '2 GB');
  });
}
