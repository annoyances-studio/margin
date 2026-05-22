// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders GitHub-Flavored Markdown for the preview pane (tables, task lists,
/// strikethrough, fenced code). Read-only; editing happens in the raw pane.
class MarkdownPreview extends StatelessWidget {
  final String data;

  const MarkdownPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      padding: const EdgeInsets.all(16),
    );
  }
}
