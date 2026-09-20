// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Formats a byte count as a short human string (binary units): `0 B`,
/// `512 B`, `1.5 KB`, `342 MB`, `1.2 GB`. One decimal place from KB up, and the
/// decimal is dropped when it is `.0` (e.g. `2 MB`, not `2.0 MB`).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.truncateToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
