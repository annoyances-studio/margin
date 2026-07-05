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
  String get openExistingFolio => 'Open an existing Folio';

  @override
  String get createFolioLocal => 'Create a Folio in the local file system';

  @override
  String get recentFolios => 'Recent';

  @override
  String get removeFromRecent => 'Remove from recent';

  @override
  String get connectWebDav => 'Connect to WebDAV';

  @override
  String get connectOneDrive => 'Connect OneDrive';

  @override
  String get oneDriveFolderLabel => 'Folder in your OneDrive';

  @override
  String get oneDriveFolderHelp => 'Created if it doesn\'t exist yet.';

  @override
  String get browseReadOnly => 'Browse read-only';

  @override
  String get browseReadOnlyHelp => 'Read a shared folder without changing it';

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
  String get closeMargin => 'Close Margin';

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
  String get syncAnyway => 'Sync anyway';

  @override
  String get copyNote => 'Copy note';

  @override
  String get specialCopy => 'Special Copy…';

  @override
  String get copyFormatted => 'Formatted (for Word, web)';

  @override
  String get copyAsMarkdown => 'Markdown source';

  @override
  String get copyAsPlainText => 'Plain text';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get copyError => 'Copy error';

  @override
  String get checkingForUpdates => 'Checking for the latest…';

  @override
  String get pasteAsMarkdown => 'Paste as Markdown';

  @override
  String get downloadingImages => 'Downloading images…';

  @override
  String get emptySyncWarning =>
      'This Folio now looks empty. Syncing will delete its contents on the other side.';

  @override
  String get searchNotes => 'Search notes…';

  @override
  String get searchNoResults => 'No matching notes.';

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
  String get openContainingFolder => 'Open containing folder';

  @override
  String get openFolderNote => 'Folder note (README.md)';

  @override
  String get refreshTree => 'Refresh (reload from disk)';

  @override
  String get backlinks => 'Backlinks';

  @override
  String get noBacklinks => 'No notes link here yet.';

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

  @override
  String get startMinimized => 'Start minimized (in the tray)';

  @override
  String get dropToAttach => 'Drop to attach to this note';

  @override
  String get dropNeedsOpenNote => 'Open a note first to attach files';

  @override
  String get wordWrap => 'Word wrap';

  @override
  String get wordWrapSubtitle =>
      'Off: long lines scroll sideways (better for tables)';
}
