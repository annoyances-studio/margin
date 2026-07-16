// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../find/find_session.dart';

/// The slim in-note find bar (Ctrl+F): a query field, a hit counter, case
/// toggle, prev/next, and close. Drives a [FindSession]; the editor highlight
/// and preview scroll react to that same session.
///
/// Enter → next, Shift+Enter → previous, Esc → close. The field autofocuses and
/// selects its text on open so a fresh Ctrl+F is type-to-replace.
class FindBar extends StatefulWidget {
  final FindSession session;

  /// Closes the bar and returns focus to the editor.
  final VoidCallback onClose;

  const FindBar({super.key, required this.session, required this.onClose});

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _field =
      TextEditingController(text: widget.session.query);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Select the existing query so reopening find and typing replaces it.
    _field.selection =
        TextSelection(baseOffset: 0, extentOffset: _field.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.session.previous();
      } else {
        widget.session.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _counter(AppLocalizations l10n) {
    final session = widget.session;
    if (session.query.isEmpty) return '';
    if (session.matchCount == 0) return l10n.findNoMatches;
    return l10n.findMatchCount(session.activeIndex + 1, session.matchCount);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = widget.session;
    final hasMatches = session.matchCount > 0;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            // Flexible so the bar fits any pane width (it can get narrow beside
            // the tree) without overflowing.
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('findField'),
                  controller: _field,
                  focusNode: _focus,
                  onChanged: session.setQuery,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l10n.findHint,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              // Reserve room so the buttons don't jitter as the count changes.
              width: 72,
              child: Text(
                _counter(l10n),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
            IconButton(
              tooltip: l10n.findCaseSensitive,
              isSelected: session.caseSensitive,
              onPressed: () => session.setCaseSensitive(!session.caseSensitive),
              visualDensity: VisualDensity.compact,
              icon: const Text(
                'Aa',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: l10n.findPreviousMatch,
              onPressed: hasMatches ? session.previous : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            ),
            IconButton(
              tooltip: l10n.findNextMatch,
              onPressed: hasMatches ? session.next : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
            IconButton(
              tooltip: l10n.close,
              onPressed: widget.onClose,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
