// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Margin';

  @override
  String get tagline => 'Plain Markdown notes in a folder you control.';

  @override
  String get openDeviceNotes => 'Open this device\'s notes';

  @override
  String get openFolio => 'Open a Folio';

  @override
  String get createFolio => 'Create a Folio';

  @override
  String get connectWebDav => 'Connect to WebDAV';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get connect => 'Connect';

  @override
  String syncing(int completed, int total) {
    return 'Syncing $completed of $total…';
  }

  @override
  String get nameFolioTitle => 'Name this Folio';

  @override
  String get folioNameLabel => 'Folio name';

  @override
  String get closeFolio => 'Close Folio';

  @override
  String get openFolioInFileManager => 'Open Folio in file manager';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get open => 'Open';

  @override
  String get settings => 'Settings';

  @override
  String get more => 'More';

  @override
  String get alwaysOnTop => 'Always on top';

  @override
  String get syncNow => 'Sync now';

  @override
  String get hideFolders => 'Hide folders';

  @override
  String get showFolders => 'Show folders';

  @override
  String get folders => 'Folders';

  @override
  String get editor => 'Editor';

  @override
  String get preview => 'Preview';

  @override
  String get split => 'Split';

  @override
  String get splitEditorPreview => 'Split (editor + preview)';

  @override
  String get attachFile => 'Attach file';

  @override
  String get newNote => 'New note';

  @override
  String get noteName => 'Note name';

  @override
  String get folderColon => 'Folder:';

  @override
  String get createFolderFirst => 'Create a folder first (Folders page).';

  @override
  String get selectNoteToEdit => 'Select a note to edit.';

  @override
  String get selectNoteToPreview => 'Select a note to preview.';

  @override
  String get writeInMarkdown => 'Write in Markdown...';

  @override
  String get noTarget => '(no target)';

  @override
  String get newTopLevelFolder => 'New top-level folder';

  @override
  String get newSubfolder => 'New subfolder';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get renameEllipsis => 'Rename…';

  @override
  String get setColorEllipsis => 'Set color…';

  @override
  String get openInFileManager => 'Open in file manager';

  @override
  String get folderName => 'Folder name';

  @override
  String get folderActions => 'Folder actions';

  @override
  String get noteActions => 'Note actions';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get deleteNote => 'Delete note';

  @override
  String get emptyFolders => 'No folders yet.\nUse \"New folder\" to start.';

  @override
  String get folderColor => 'Folder color';

  @override
  String get noColor => 'No color';

  @override
  String deleteFolderTitle(String name) {
    return 'Delete folder \"$name\"?';
  }

  @override
  String get deleteFolderBody =>
      'This deletes the folder and all notes inside it.';

  @override
  String deleteNoteTitle(String name) {
    return 'Delete note \"$name\"?';
  }

  @override
  String get deleteNoteBody => 'This permanently removes the note file.';

  @override
  String get defaultView => 'Default view';

  @override
  String get defaultViewForNotes => 'Default view for notes';

  @override
  String get viewNoteSpecified => 'Note specified';

  @override
  String get startAtLogin => 'Start Margin when I log in';
}
