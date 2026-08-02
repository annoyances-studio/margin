import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// The application name.
  ///
  /// In en, this message translates to:
  /// **'Margin•'**
  String get appName;

  /// Landing-screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Plain Markdown notes in a folder you control.'**
  String get tagline;

  /// Landing button: open the on-device notes folder.
  ///
  /// In en, this message translates to:
  /// **'Open this device\'s notes'**
  String get openDeviceNotes;

  /// Landing button: open an existing Folio (notes folder).
  ///
  /// In en, this message translates to:
  /// **'Open a Folio'**
  String get openFolio;

  /// Landing button: create a new Folio.
  ///
  /// In en, this message translates to:
  /// **'Create a Folio'**
  String get createFolio;

  /// Open-a-Folio option: pick an existing local Folio folder.
  ///
  /// In en, this message translates to:
  /// **'Open an existing Folio'**
  String get openExistingFolio;

  /// Open-a-Folio option: create a new Folio in a chosen local folder.
  ///
  /// In en, this message translates to:
  /// **'Create a Folio in the local file system'**
  String get createFolioLocal;

  /// Landing section label above the recently opened Folios.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentFolios;

  /// Tooltip on the X that removes an entry from the recent Folios.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent'**
  String get removeFromRecent;

  /// Landing button / dialog title for adding a WebDAV Folio.
  ///
  /// In en, this message translates to:
  /// **'Connect to WebDAV'**
  String get connectWebDav;

  /// Landing button to start the OneDrive OAuth sign-in.
  ///
  /// In en, this message translates to:
  /// **'Connect OneDrive'**
  String get connectOneDrive;

  /// Label for the OneDrive folder path field.
  ///
  /// In en, this message translates to:
  /// **'Folder in your OneDrive'**
  String get oneDriveFolderLabel;

  /// Helper text under the OneDrive folder field.
  ///
  /// In en, this message translates to:
  /// **'Created if it doesn\'t exist yet.'**
  String get oneDriveFolderHelp;

  /// Checkbox in the connect dialogs: open the folder read-only (companion mode) instead of a managed Folio.
  ///
  /// In en, this message translates to:
  /// **'Browse read-only'**
  String get browseReadOnly;

  /// Subtitle explaining the browse-read-only checkbox.
  ///
  /// In en, this message translates to:
  /// **'Read a shared folder without changing it'**
  String get browseReadOnlyHelp;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Progress shown while caching/syncing a remote Folio.
  ///
  /// In en, this message translates to:
  /// **'Syncing {completed} of {total}…'**
  String syncing(int completed, int total);

  /// Dialog title when naming a new Folio.
  ///
  /// In en, this message translates to:
  /// **'Name this Folio'**
  String get nameFolioTitle;

  /// Text field label for a Folio's name.
  ///
  /// In en, this message translates to:
  /// **'Folio name'**
  String get folioNameLabel;

  /// Action that closes the open Folio.
  ///
  /// In en, this message translates to:
  /// **'Close Folio'**
  String get closeFolio;

  /// Desktop action that quits the app entirely (rather than hiding to the tray).
  ///
  /// In en, this message translates to:
  /// **'Close Margin'**
  String get closeMargin;

  /// Tooltip: reveal the Folio's folder in the OS file manager.
  ///
  /// In en, this message translates to:
  /// **'Open Folio in file manager'**
  String get openFolioInFileManager;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @alwaysOnTop.
  ///
  /// In en, this message translates to:
  /// **'Always on top'**
  String get alwaysOnTop;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncAnyway.
  ///
  /// In en, this message translates to:
  /// **'Sync anyway'**
  String get syncAnyway;

  /// Overflow menu item to copy the open note.
  ///
  /// In en, this message translates to:
  /// **'Copy note'**
  String get copyNote;

  /// Context-menu item opening the copy-format options.
  ///
  /// In en, this message translates to:
  /// **'Special Copy…'**
  String get specialCopy;

  /// Copy option: rich text / HTML.
  ///
  /// In en, this message translates to:
  /// **'Formatted (for Word, web)'**
  String get copyFormatted;

  /// Copy option: raw markdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown source'**
  String get copyAsMarkdown;

  /// Copy option: stripped plain text.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get copyAsPlainText;

  /// Confirmation shown after a copy.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Button to copy an error message for reporting.
  ///
  /// In en, this message translates to:
  /// **'Copy error'**
  String get copyError;

  /// Cue shown while fetching a newer version of the open note.
  ///
  /// In en, this message translates to:
  /// **'Checking for the latest…'**
  String get checkingForUpdates;

  /// Editor action: paste clipboard HTML converted to markdown.
  ///
  /// In en, this message translates to:
  /// **'Paste as Markdown'**
  String get pasteAsMarkdown;

  /// Shown while pasted remote images are being downloaded into attachments.
  ///
  /// In en, this message translates to:
  /// **'Downloading images…'**
  String get downloadingImages;

  /// Shown when a sync would propagate an apparent 'everything deleted' — guards against a flaky connection.
  ///
  /// In en, this message translates to:
  /// **'This Folio now looks empty. Syncing will delete its contents on the other side.'**
  String get emptySyncWarning;

  /// Placeholder for the note search box.
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get searchNotes;

  /// Shown when a note search has no hits.
  ///
  /// In en, this message translates to:
  /// **'No matching notes.'**
  String get searchNoResults;

  /// No description provided for @hideFolders.
  ///
  /// In en, this message translates to:
  /// **'Hide folders'**
  String get hideFolders;

  /// No description provided for @showFolders.
  ///
  /// In en, this message translates to:
  /// **'Show folders'**
  String get showFolders;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @editor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editor;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @split.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get split;

  /// No description provided for @splitEditorPreview.
  ///
  /// In en, this message translates to:
  /// **'Split (editor + preview)'**
  String get splitEditorPreview;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @noteName.
  ///
  /// In en, this message translates to:
  /// **'Note name'**
  String get noteName;

  /// No description provided for @folderColon.
  ///
  /// In en, this message translates to:
  /// **'Folder:'**
  String get folderColon;

  /// No description provided for @createFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a folder first (Folders page).'**
  String get createFolderFirst;

  /// No description provided for @selectNoteToEdit.
  ///
  /// In en, this message translates to:
  /// **'Select a note to edit.'**
  String get selectNoteToEdit;

  /// No description provided for @selectNoteToPreview.
  ///
  /// In en, this message translates to:
  /// **'Select a note to preview.'**
  String get selectNoteToPreview;

  /// No description provided for @writeInMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Write in Markdown...'**
  String get writeInMarkdown;

  /// No description provided for @noTarget.
  ///
  /// In en, this message translates to:
  /// **'(no target)'**
  String get noTarget;

  /// No description provided for @newTopLevelFolder.
  ///
  /// In en, this message translates to:
  /// **'New top-level folder'**
  String get newTopLevelFolder;

  /// No description provided for @newSubfolder.
  ///
  /// In en, this message translates to:
  /// **'New subfolder'**
  String get newSubfolder;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolder;

  /// No description provided for @renameEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get renameEllipsis;

  /// No description provided for @setColorEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Set color…'**
  String get setColorEllipsis;

  /// No description provided for @openInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Open in file manager'**
  String get openInFileManager;

  /// Note action: reveal the note's file highlighted in its folder (desktop).
  ///
  /// In en, this message translates to:
  /// **'Open containing folder'**
  String get openContainingFolder;

  /// Tooltip on the badge marking a folder that has a folder-level note.
  ///
  /// In en, this message translates to:
  /// **'Folder note (README.md)'**
  String get openFolderNote;

  /// App-bar action: rebuild the tree to pick up files changed outside the app.
  ///
  /// In en, this message translates to:
  /// **'Refresh (reload from disk)'**
  String get refreshTree;

  /// App-bar action / dialog title: notes that link to the open note.
  ///
  /// In en, this message translates to:
  /// **'Backlinks'**
  String get backlinks;

  /// Shown in the backlinks dialog when nothing references the open note.
  ///
  /// In en, this message translates to:
  /// **'No notes link here yet.'**
  String get noBacklinks;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @folderActions.
  ///
  /// In en, this message translates to:
  /// **'Folder actions'**
  String get folderActions;

  /// No description provided for @noteActions.
  ///
  /// In en, this message translates to:
  /// **'Note actions'**
  String get noteActions;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// No description provided for @deleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get deleteNote;

  /// No description provided for @emptyFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders yet.\nUse \"New folder\" to start.'**
  String get emptyFolders;

  /// No description provided for @folderColor.
  ///
  /// In en, this message translates to:
  /// **'Folder color'**
  String get folderColor;

  /// No description provided for @noColor.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get noColor;

  /// Confirm-delete dialog title for a folder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder \"{name}\"?'**
  String deleteFolderTitle(String name);

  /// No description provided for @deleteFolderBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the folder and all notes inside it.'**
  String get deleteFolderBody;

  /// Confirm-delete dialog title for a note.
  ///
  /// In en, this message translates to:
  /// **'Delete note \"{name}\"?'**
  String deleteNoteTitle(String name);

  /// No description provided for @deleteNoteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the note file.'**
  String get deleteNoteBody;

  /// No description provided for @defaultView.
  ///
  /// In en, this message translates to:
  /// **'Default view'**
  String get defaultView;

  /// No description provided for @defaultViewForNotes.
  ///
  /// In en, this message translates to:
  /// **'Default view for notes'**
  String get defaultViewForNotes;

  /// No description provided for @viewNoteSpecified.
  ///
  /// In en, this message translates to:
  /// **'Note specified'**
  String get viewNoteSpecified;

  /// No description provided for @startAtLogin.
  ///
  /// In en, this message translates to:
  /// **'Start Margin when I log in'**
  String get startAtLogin;

  /// Sub-option of run-at-login: launch hidden to the tray.
  ///
  /// In en, this message translates to:
  /// **'Start minimized (in the tray)'**
  String get startMinimized;

  /// Overlay shown while dragging files over the editor; the drop will attach them.
  ///
  /// In en, this message translates to:
  /// **'Drop to attach to this note'**
  String get dropToAttach;

  /// Overlay shown while dragging files when no note is open to receive them.
  ///
  /// In en, this message translates to:
  /// **'Open a note first to attach files'**
  String get dropNeedsOpenNote;

  /// Settings toggle: soft-wrap long lines in the editor.
  ///
  /// In en, this message translates to:
  /// **'Word wrap'**
  String get wordWrap;

  /// Explains what turning word wrap off does.
  ///
  /// In en, this message translates to:
  /// **'Off: long lines scroll sideways (better for tables)'**
  String get wordWrapSubtitle;

  /// Tooltip/label for the in-note find feature (Ctrl+F).
  ///
  /// In en, this message translates to:
  /// **'Find in note'**
  String get findInNote;

  /// Placeholder in the in-note find field.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findHint;

  /// Tooltip for the find bar's next-match button.
  ///
  /// In en, this message translates to:
  /// **'Next match (Enter)'**
  String get findNextMatch;

  /// Tooltip for the find bar's previous-match button.
  ///
  /// In en, this message translates to:
  /// **'Previous match (Shift+Enter)'**
  String get findPreviousMatch;

  /// Find bar hit counter, e.g. '3 of 12'.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String findMatchCount(int current, int total);

  /// Find bar counter text when the query matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get findNoMatches;

  /// Tooltip for the find bar's case-sensitivity toggle.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get findCaseSensitive;

  /// Tooltip for the navigate-back button (previous note in history).
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get navigateBack;

  /// Tooltip for the navigate-forward button (next note in history).
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get navigateForward;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
