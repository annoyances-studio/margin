// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/clipboard_service.dart';

/// Builds a minimal clipboard DIB: a BITMAPINFOHEADER with the given fields
/// followed by [pixelBytes] of pixel data.
Uint8List _dib({
  int headerSize = 40,
  int bitCount = 32,
  int compression = 0, // BI_RGB
  int clrUsed = 0,
  int pixelBytes = 16,
}) {
  final dib = Uint8List(headerSize + clrUsed * 4 + pixelBytes);
  final data = ByteData.sublistView(dib);
  data.setUint32(0, headerSize, Endian.little);
  data.setUint16(14, bitCount, Endian.little);
  data.setUint32(16, compression, Endian.little);
  data.setUint32(32, clrUsed, Endian.little);
  return dib;
}

void main() {
  test('a 32-bit BI_RGB DIB (PrintScreen) gets a valid BMP header', () {
    final dib = _dib();
    final bmp = dibToBmp(dib)!;

    expect(bmp[0], 0x42); // 'B'
    expect(bmp[1], 0x4D); // 'M'
    final data = ByteData.sublistView(bmp);
    expect(data.getUint32(2, Endian.little), 14 + dib.length); // file size
    expect(data.getUint32(10, Endian.little), 14 + 40); // pixels after header
    // The DIB bytes follow the file header untouched.
    expect(bmp.sublist(14), dib);
  });

  test('BI_BITFIELDS masks after a plain header shift the pixel offset', () {
    final bmp = dibToBmp(_dib(compression: 3, pixelBytes: 28))!;
    expect(ByteData.sublistView(bmp).getUint32(10, Endian.little),
        14 + 40 + 12);
  });

  test('a palette DIB shifts the pixel offset past the palette', () {
    // Explicit 16-entry palette.
    final explicit = dibToBmp(_dib(bitCount: 8, clrUsed: 16, pixelBytes: 4))!;
    expect(ByteData.sublistView(explicit).getUint32(10, Endian.little),
        14 + 40 + 16 * 4);

    // biClrUsed 0 at 8bpp means a full 256-entry palette (present in the
    // pixel area of this fixture).
    final implicit =
        dibToBmp(_dib(bitCount: 8, clrUsed: 0, pixelBytes: 256 * 4 + 4))!;
    expect(ByteData.sublistView(implicit).getUint32(10, Endian.little),
        14 + 40 + 256 * 4);
  });

  test('a V5 header (Snipping Tool) keeps its embedded masks', () {
    final bmp = dibToBmp(_dib(headerSize: 124, compression: 3))!;
    // No extra 12 mask bytes: V4/V5 headers carry the masks inside.
    expect(ByteData.sublistView(bmp).getUint32(10, Endian.little), 14 + 124);
  });

  test('garbage is rejected', () {
    expect(dibToBmp(Uint8List(0)), isNull);
    expect(dibToBmp(Uint8List(10)), isNull);
    // Header claiming to be larger than the data.
    final lying = _dib(pixelBytes: 0);
    ByteData.sublistView(lying).setUint32(0, 9999, Endian.little);
    expect(dibToBmp(lying), isNull);
  });
}
