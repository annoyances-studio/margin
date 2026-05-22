// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Preset folder accent colors (label and `#RRGGBB` hex).
const List<({String label, String hex})> folderColorPalette = [
  (label: 'Red', hex: '#E57373'),
  (label: 'Orange', hex: '#FFB74D'),
  (label: 'Amber', hex: '#FFD54F'),
  (label: 'Green', hex: '#81C784'),
  (label: 'Teal', hex: '#4DB6AC'),
  (label: 'Blue', hex: '#64B5F6'),
  (label: 'Indigo', hex: '#7986CB'),
  (label: 'Purple', hex: '#BA68C8'),
  (label: 'Pink', hex: '#F06292'),
  (label: 'Grey', hex: '#90A4AE'),
];

/// Parses a `#RRGGBB` (or `RRGGBB`) hex string into a [Color]. Returns `null`
/// for null or unparseable input.
Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
