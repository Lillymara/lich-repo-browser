import 'dart:typed_data';

import 'catalog_entry.dart';

/// A place scripts can be browsed and downloaded from.
abstract class RepoSource {
  /// Stable identifier, used as [CatalogEntry.sourceId].
  String get id;

  /// Human-readable name for the UI.
  String get displayName;

  Future<List<CatalogEntry>> fetchCatalog();

  Future<EntryDetails> fetchDetails(CatalogEntry entry);

  Future<Uint8List> download(CatalogEntry entry, {String? version});
}

class RepoException implements Exception {
  RepoException(this.message);
  final String message;
  @override
  String toString() => 'RepoException: $message';
}
