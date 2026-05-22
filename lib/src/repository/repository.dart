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
import 'repository_exception.dart';
import 'repository_properties.dart';

/// A Margin repository: a [StorageBackend] plus its validated root
/// [RepositoryProperties].
///
/// Use [open] to load an existing repository and [create] to initialize a new
/// one. Both are built purely on the storage primitives, so they work over any
/// backend (local folder, WebDAV, ...).
class Repository {
  final StorageBackend backend;
  final RepositoryProperties properties;

  const Repository._(this.backend, this.properties);

  String get id => properties.id;
  String get name => properties.name;
  List<Endpoint> get endpoints => properties.endpoints;

  /// Opens an existing repository on [backend].
  ///
  /// Throws [NotAMarginRepositoryException] if there is no valid root
  /// `properties.yaml`, or [IncompatibleSchemaException] if the repository was
  /// written by a newer schema version than this build supports.
  static Future<Repository> open(StorageBackend backend) async {
    final Uint8List bytes;
    try {
      bytes = await backend.read(RepositoryProperties.fileName);
    } on NotFoundException {
      throw const NotAMarginRepositoryException(
        'No properties.yaml at the repository root',
      );
    }

    final RepositoryProperties properties;
    try {
      properties = RepositoryProperties.parse(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw NotAMarginRepositoryException('Invalid properties.yaml: ${e.message}');
    }

    if (properties.schemaVersion > RepositoryProperties.currentSchemaVersion) {
      throw IncompatibleSchemaException(
        properties.schemaVersion,
        RepositoryProperties.currentSchemaVersion,
      );
    }

    return Repository._(backend, properties);
  }

  /// Creates a new repository on [backend], writing a fresh root
  /// `properties.yaml` with a generated id.
  ///
  /// Throws [RepositoryExistsException] if a repository already exists there.
  /// [uuid] and [now] may be supplied for deterministic tests.
  static Future<Repository> create(
    StorageBackend backend, {
    required String name,
    String appVersion = marginAppVersion,
    List<Endpoint> endpoints = const [],
    Uuid? uuid,
    DateTime? now,
  }) async {
    if (await backend.exists(RepositoryProperties.fileName)) {
      throw const RepositoryExistsException(
        'A repository already exists at this location',
      );
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final properties = RepositoryProperties(
      schemaVersion: RepositoryProperties.currentSchemaVersion,
      id: (uuid ?? const Uuid()).v4(),
      name: name,
      created: timestamp,
      updated: timestamp,
      appVersion: appVersion,
      endpoints: endpoints,
    );

    await backend.write(
      RepositoryProperties.fileName,
      Uint8List.fromList(utf8.encode(properties.toYaml())),
    );

    return Repository._(backend, properties);
  }
}
