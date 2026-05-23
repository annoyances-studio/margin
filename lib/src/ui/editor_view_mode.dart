// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// How the editor area is presented (DESIGN.md):
/// - [edit]: inline-styled Markdown editor (the formatting is the typing).
/// - [split]: editor beside the rendered preview.
/// - [preview]: rendered Markdown only, read-only.
enum EditorViewMode { edit, split, preview }

/// The app-wide policy for choosing a note's initial view.
enum DefaultViewPolicy {
  /// Honor each note's own stored view (falling back to the per-note default).
  noteSpecified,
  editor,
  split,
  preview,
}

extension EditorViewModeId on EditorViewMode {
  /// Stable string id used in YAML and preferences.
  String get id => switch (this) {
        EditorViewMode.edit => 'editor',
        EditorViewMode.split => 'split',
        EditorViewMode.preview => 'preview',
      };
}

EditorViewMode? editorViewModeFromId(String? id) => switch (id) {
      'editor' => EditorViewMode.edit,
      'split' => EditorViewMode.split,
      'preview' => EditorViewMode.preview,
      _ => null,
    };

extension DefaultViewPolicyId on DefaultViewPolicy {
  String get id => switch (this) {
        DefaultViewPolicy.noteSpecified => 'note',
        DefaultViewPolicy.editor => 'editor',
        DefaultViewPolicy.split => 'split',
        DefaultViewPolicy.preview => 'preview',
      };

  /// The fixed [EditorViewMode] this policy forces, or null for
  /// [DefaultViewPolicy.noteSpecified].
  EditorViewMode? get forcedMode => switch (this) {
        DefaultViewPolicy.noteSpecified => null,
        DefaultViewPolicy.editor => EditorViewMode.edit,
        DefaultViewPolicy.split => EditorViewMode.split,
        DefaultViewPolicy.preview => EditorViewMode.preview,
      };
}

DefaultViewPolicy defaultViewPolicyFromId(String? id) => switch (id) {
      'editor' => DefaultViewPolicy.editor,
      'split' => DefaultViewPolicy.split,
      'preview' => DefaultViewPolicy.preview,
      _ => DefaultViewPolicy.noteSpecified,
    };
