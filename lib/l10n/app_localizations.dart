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
  /// **'Margin'**
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

  /// Landing button / dialog title for adding a WebDAV Folio.
  ///
  /// In en, this message translates to:
  /// **'Connect to WebDAV'**
  String get connectWebDav;

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

  /// Shown when a sync would propagate an apparent 'everything deleted' — guards against a flaky connection.
  ///
  /// In en, this message translates to:
  /// **'This Folio now looks empty. Syncing will delete its contents on the other side.'**
  String get emptySyncWarning;

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
