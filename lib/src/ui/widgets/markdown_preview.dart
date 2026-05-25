// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../desktop/file_reveal.dart';
import '../link_target.dart';

/// Renders GitHub-Flavored Markdown for the preview pane (tables, task lists,
/// strikethrough, fenced code). Read-only; editing happens in the raw pane.
///
/// Relative image links (e.g. `_attachments/pic.png`) are resolved against
/// [imageBaseDir] (the open note's folder) and loaded from disk; http(s) images
/// load from the network.
class MarkdownPreview extends StatelessWidget {
  final String data;
  final String? imageBaseDir;

  const MarkdownPreview({super.key, required this.data, this.imageBaseDir});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      padding: const EdgeInsets.all(16),
      sizedImageBuilder: _buildImage,
      onTapLink: (text, href, title) => _openLink(href),
    );
  }

  void _openLink(String? href) {
    if (href == null) return;
    final target = resolveLinkTarget(href, imageBaseDir);
    if (target != null) openWithDefaultApp(target);
  }

  Widget _buildImage(MarkdownImageConfig config) {
    final uri = config.uri;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString(), width: config.width, height: config.height);
    }

    final path = resolveLinkTarget(uri.path, imageBaseDir);
    if (path == null) {
      return const Icon(Icons.image_not_supported_outlined);
    }
    return Image.file(
      File(path),
      width: config.width,
      height: config.height,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }
}
