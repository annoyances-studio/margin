// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

/// A one-shot "jump to this line" signal from the go-to-line bar to the editor.
/// A [ChangeNotifier] (rather than a value) so re-requesting the same line still
/// fires — asking for line 5 twice should jump twice.
class GoToLineRequest extends ChangeNotifier {
  int _line = 0;

  /// The most recently requested 1-based line.
  int get line => _line;

  void go(int line) {
    _line = line;
    notifyListeners();
  }
}

/// The slim go-to-line bar (Ctrl+G): a number field that, on Enter, jumps the
/// editor to that line. Esc closes. Editor/split only (preview has no source
/// lines). Autofocuses on open.
class GoToLineBar extends StatefulWidget {
  /// Total lines in the note, shown as a hint and used to clamp input.
  final int lineCount;
  final void Function(int line) onSubmit;
  final VoidCallback onClose;

  const GoToLineBar({
    super.key,
    required this.lineCount,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  State<GoToLineBar> createState() => _GoToLineBarState();
}

class _GoToLineBarState extends State<GoToLineBar> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
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

  void _submit() {
    final n = int.tryParse(_field.text.trim());
    if (n != null) widget.onSubmit(n);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.numbers, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('goToLineField'),
                  controller: _field,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _submit(),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l10n.goToLineHint(widget.lineCount),
                  ),
                ),
              ),
            ),
            const Spacer(),
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
