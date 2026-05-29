// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Margin';

  @override
  String get tagline => 'Notas Markdown en una carpeta que tú controlas.';

  @override
  String get openDeviceNotes => 'Abrir las notas de este dispositivo';

  @override
  String get openFolio => 'Abrir un Folio';

  @override
  String get createFolio => 'Crear un Folio';

  @override
  String get connectWebDav => 'Conectar a WebDAV';

  @override
  String get connectOneDrive => 'Conectar OneDrive';

  @override
  String get oneDriveFolderLabel => 'Carpeta en tu OneDrive';

  @override
  String get oneDriveFolderHelp => 'Se crea si aún no existe.';

  @override
  String get serverUrl => 'URL del servidor';

  @override
  String get username => 'Usuario';

  @override
  String get password => 'Contraseña';

  @override
  String get connect => 'Conectar';

  @override
  String syncing(int completed, int total) {
    return 'Sincronizando $completed de $total…';
  }

  @override
  String get nameFolioTitle => 'Nombra este Folio';

  @override
  String get folioNameLabel => 'Nombre del Folio';

  @override
  String get closeFolio => 'Cerrar Folio';

  @override
  String get closeMargin => 'Cerrar Margin';

  @override
  String get openFolioInFileManager =>
      'Abrir el Folio en el explorador de archivos';

  @override
  String get cancel => 'Cancelar';

  @override
  String get create => 'Crear';

  @override
  String get rename => 'Renombrar';

  @override
  String get delete => 'Eliminar';

  @override
  String get close => 'Cerrar';

  @override
  String get save => 'Guardar';

  @override
  String get open => 'Abrir';

  @override
  String get settings => 'Ajustes';

  @override
  String get more => 'Más';

  @override
  String get alwaysOnTop => 'Siempre visible';

  @override
  String get syncNow => 'Sincronizar ahora';

  @override
  String get syncAnyway => 'Sincronizar de todos modos';

  @override
  String get emptySyncWarning =>
      'Este Folio parece vacío ahora. Sincronizar eliminará su contenido en el otro lado.';

  @override
  String get hideFolders => 'Ocultar carpetas';

  @override
  String get showFolders => 'Mostrar carpetas';

  @override
  String get folders => 'Carpetas';

  @override
  String get editor => 'Editor';

  @override
  String get preview => 'Vista previa';

  @override
  String get split => 'Dividido';

  @override
  String get splitEditorPreview => 'Dividido (editor + vista previa)';

  @override
  String get attachFile => 'Adjuntar archivo';

  @override
  String get newNote => 'Nueva nota';

  @override
  String get noteName => 'Nombre de la nota';

  @override
  String get folderColon => 'Carpeta:';

  @override
  String get createFolderFirst => 'Crea primero una carpeta (página Carpetas).';

  @override
  String get selectNoteToEdit => 'Selecciona una nota para editar.';

  @override
  String get selectNoteToPreview => 'Selecciona una nota para previsualizar.';

  @override
  String get writeInMarkdown => 'Escribe en Markdown...';

  @override
  String get noTarget => '(sin destino)';

  @override
  String get newTopLevelFolder => 'Nueva carpeta de nivel superior';

  @override
  String get newSubfolder => 'Nueva subcarpeta';

  @override
  String get renameFolder => 'Renombrar carpeta';

  @override
  String get renameEllipsis => 'Renombrar…';

  @override
  String get setColorEllipsis => 'Establecer color…';

  @override
  String get openInFileManager => 'Abrir en el explorador de archivos';

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get folderActions => 'Acciones de carpeta';

  @override
  String get noteActions => 'Acciones de nota';

  @override
  String get deleteFolder => 'Eliminar carpeta';

  @override
  String get deleteNote => 'Eliminar nota';

  @override
  String get emptyFolders =>
      'Aún no hay carpetas.\nUsa \"Nueva carpeta\" para empezar.';

  @override
  String get folderColor => 'Color de la carpeta';

  @override
  String get noColor => 'Sin color';

  @override
  String deleteFolderTitle(String name) {
    return '¿Eliminar la carpeta \"$name\"?';
  }

  @override
  String get deleteFolderBody =>
      'Esto elimina la carpeta y todas las notas que contiene.';

  @override
  String deleteNoteTitle(String name) {
    return '¿Eliminar la nota \"$name\"?';
  }

  @override
  String get deleteNoteBody =>
      'Esto elimina permanentemente el archivo de la nota.';

  @override
  String get defaultView => 'Vista predeterminada';

  @override
  String get defaultViewForNotes => 'Vista predeterminada para notas';

  @override
  String get viewNoteSpecified => 'Según la nota';

  @override
  String get startAtLogin => 'Iniciar Margin al iniciar sesión';
}
