// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:path/path.dart' as p;

/// File extensions we treat as previewable images.
const _imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
};

/// Whether [href] points outside the repository — an http(s)/mailto/etc. URL
/// rather than a relative attachment path. A `file:` scheme is treated as local.
bool isExternalUrl(String href) {
  final uri = Uri.tryParse(href);
  return uri != null && uri.hasScheme && uri.scheme != 'file';
}

/// Whether [target] (a path or URL) looks like an image by its extension.
bool isImageTarget(String target) =>
    _imageExtensions.contains(p.extension(target).toLowerCase());

/// Resolves a Markdown link [href] to something the OS can open.
///
/// Returns external URLs unchanged; resolves relative links into an absolute
/// filesystem path joined against [baseDir] (the open note's folder). Returns
/// null when there is nothing to open (empty href, or a relative link with no
/// known base directory).
String? resolveLinkTarget(String href, String? baseDir) {
  if (href.isEmpty) return null;
  if (isExternalUrl(href)) return href;
  if (baseDir == null) return null;
  // Decode percent-escapes (e.g. %20 -> space). Raw non-ASCII names such as
  // Japanese aren't valid percent-encoding and make Uri.decodeFull throw
  // ArgumentError; a malformed '%' likewise. In either case the href is
  // already literal, so fall back to it rather than crashing the caller.
  String decoded;
  try {
    decoded = Uri.decodeFull(href);
  } catch (_) {
    decoded = href;
  }
  return p.normalize(p.join(baseDir, decoded));
}
