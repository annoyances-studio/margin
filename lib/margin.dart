// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Margin: a multiplatform Markdown note-taking app. Plain files in a folder
/// you control. This library exposes the storage and Folio layers; see
/// DESIGN.md for the architecture.
library;

export 'src/app_info.dart';

// Storage layer.
export 'src/storage/content_codec.dart';
export 'src/storage/local_folder_backend.dart';
export 'src/storage/memory_backend.dart';
export 'src/storage/storage_backend.dart';
export 'src/storage/storage_entry.dart';
export 'src/storage/storage_exception.dart';
export 'src/storage/webdav_backend.dart';

// Folio layer.
export 'src/folio/endpoint.dart';
export 'src/folio/folder_properties.dart';
export 'src/folio/note.dart';
export 'src/folio/folio.dart';
export 'src/folio/folio_exception.dart';
export 'src/folio/folio_properties.dart';

// Content layer.
export 'src/content/content_exception.dart';
export 'src/content/content_service.dart';
export 'src/content/tree_node.dart';

// Sync layer.
export 'src/sync/content_hash.dart';
export 'src/sync/sync_action.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_planner.dart';
export 'src/sync/sync_state.dart';
