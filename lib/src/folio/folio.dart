// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../app_info.dart';
import '../storage/storage_backend.dart';
import '../storage/storage_exception.dart';
import 'endpoint.dart';
import 'folio_exception.dart';
import 'folio_properties.dart';

/// A Margin Folio: a [StorageBackend] plus its validated root
/// [FolioProperties].
///
/// Use [open] to load an existing Folio and [create] to initialize a new
/// one. Both are built purely on the storage primitives, so they work over any
/// backend (local folder, WebDAV, ...).
class Folio {
  final StorageBackend backend;
  final FolioProperties properties;

  const Folio._(this.backend, this.properties);

  String get id => properties.id;
  String get name => properties.name;
  List<Endpoint> get endpoints => properties.endpoints;

  /// Opens an existing Folio on [backend].
  ///
  /// Throws [NotAMarginFolioException] if there is no valid root
  /// `properties.yaml`, or [IncompatibleSchemaException] if the Folio was
  /// written by a newer schema version than this build supports.
  static Future<Folio> open(StorageBackend backend) async {
    final Uint8List bytes;
    try {
      bytes = await backend.read(FolioProperties.fileName);
    } on NotFoundException {
      throw const NotAMarginFolioException(
        'No properties.yaml at the Folio root',
      );
    }

    final FolioProperties properties;
    try {
      properties = FolioProperties.parse(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw NotAMarginFolioException('Invalid properties.yaml: ${e.message}');
    }

    if (properties.schemaVersion > FolioProperties.currentSchemaVersion) {
      throw IncompatibleSchemaException(
        properties.schemaVersion,
        FolioProperties.currentSchemaVersion,
      );
    }

    return Folio._(backend, properties);
  }

  /// Creates a new Folio on [backend], writing a fresh root
  /// `properties.yaml` with a generated id.
  ///
  /// Throws [FolioExistsException] if a Folio already exists there.
  /// [uuid] and [now] may be supplied for deterministic tests.
  static Future<Folio> create(
    StorageBackend backend, {
    required String name,
    String appVersion = marginAppVersion,
    List<Endpoint> endpoints = const [],
    Uuid? uuid,
    DateTime? now,
  }) async {
    if (await backend.exists(FolioProperties.fileName)) {
      throw const FolioExistsException(
        'A Folio already exists at this location',
      );
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final properties = FolioProperties(
      schemaVersion: FolioProperties.currentSchemaVersion,
      id: (uuid ?? const Uuid()).v4(),
      name: name,
      created: timestamp,
      updated: timestamp,
      appVersion: appVersion,
      endpoints: endpoints,
    );

    await backend.write(
      FolioProperties.fileName,
      Uint8List.fromList(utf8.encode(properties.toYaml())),
    );

    return Folio._(backend, properties);
  }
}
