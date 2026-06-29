// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../l10n/app_localizations.dart';
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

  /// Scroll physics for the rendered content. The mobile preview page passes
  /// [AlwaysScrollableScrollPhysics] so pull-to-refresh works on short notes.
  final ScrollPhysics? physics;

  /// Opens the formatted-copy chooser ("Special Copy"). Null hides the item.
  final VoidCallback? onSpecialCopy;

  /// Follows a tapped link [target] (a sibling `.md` opens in-app, else via the
  /// OS). When null, falls back to opening the resolved target directly.
  final void Function(String target)? onOpenLink;

  const MarkdownPreview({
    super.key,
    required this.data,
    this.imageBaseDir,
    this.physics,
    this.onSpecialCopy,
    this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A subtly distinct surface tone tells the rendered preview apart from the
    // raw editor at a glance (it reads as "rendered", not "editable").
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      // SelectionArea gives proper cross-block text selection (flutter_markdown's
      // own `selectable:` only selects within a single block), plus a place to
      // attach the Special Copy action.
      child: SelectionArea(
        contextMenuBuilder: _buildSelectionMenu,
        child: Markdown(
          data: data,
          selectable: false, // SelectionArea owns selection now
          physics: physics,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          padding: const EdgeInsets.all(16),
          styleSheet: _styleSheet(theme),
          sizedImageBuilder: _buildImage,
          onTapLink: (text, href, title) => _openLink(href),
        ),
      ),
    );
  }

  /// Theme-derived styles, overriding flutter_markdown's defaults where they
  /// don't adapt to the color scheme — notably the block quote, whose default
  /// is a hardcoded light-blue box that renders white-on-light-blue (i.e.
  /// unreadable) in dark mode. We use a subtle surface fill, on-surface text,
  /// and a primary accent bar instead.
  MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: scheme.primary, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    );
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableState,
  ) {
    final items = List<ContextMenuButtonItem>.from(
      selectableState.contextMenuButtonItems,
    );
    if (onSpecialCopy != null) {
      items.add(ContextMenuButtonItem(
        label: AppLocalizations.of(context).specialCopy,
        onPressed: () {
          ContextMenuController.removeAny();
          onSpecialCopy!();
        },
      ));
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _openLink(String? href) {
    if (href == null) return;
    if (onOpenLink != null) {
      onOpenLink!(href);
      return;
    }
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
