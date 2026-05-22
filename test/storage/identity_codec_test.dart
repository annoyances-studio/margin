// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/storage/content_codec.dart';

void main() {
  group('IdentityCodec', () {
    const codec = IdentityCodec();

    test('encode returns the same bytes', () {
      final input = Uint8List.fromList(utf8.encode('hello'));
      expect(codec.encode(input), equals(input));
    });

    test('decode returns the same bytes', () {
      final input = Uint8List.fromList([0, 1, 2, 255]);
      expect(codec.decode(input), equals(input));
    });

    test('decode(encode(x)) == x for all byte values', () {
      final input = Uint8List.fromList(List<int>.generate(256, (i) => i));
      expect(codec.decode(codec.encode(input)), equals(input));
    });
  });
}
