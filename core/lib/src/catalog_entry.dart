/// One downloadable thing (script, data file, map image, ...) from any source.
///
/// Fields that only one kind of source provides are nullable: the Lich repo
/// has downloads/ratings/comments, Jinx has version/asset type/header URL.
class CatalogEntry {
  CatalogEntry({
    required this.sourceId,
    required this.name,
    this.type = 'script',
    this.game,
    this.author,
    this.version,
    this.tags = const [],
    this.lastUpdated,
    this.size,
    this.downloads,
    this.ratingTotal,
    this.ratingCount,
    this.comments,
    this.sha1Hex,
    this.path,
    this.headerPath,
  });

  /// Which source this came from, e.g. `lich` or `jinx:elanthia-online`.
  final String sourceId;

  /// Bare file name, e.g. `bigshot.lic`.
  final String name;

  /// `script`, `data`, `engine`, `map`, ...
  final String type;

  final String? game;
  final String? author;
  final String? version;
  final List<String> tags;
  final DateTime? lastUpdated;
  final int? size;
  final int? downloads;
  final int? ratingTotal;
  final int? ratingCount;
  final String? comments;

  /// SHA-1 of the file as lowercase hex (Jinx only; its manifest calls this
  /// field `md5` but it is a base64 SHA-1).
  final String? sha1Hex;

  /// Source-relative path used to download the file (Jinx only).
  final String? path;

  /// Source-relative path to the script header (Jinx only).
  final String? headerPath;

  Map<String, Object?> toJson() => {
        'sourceId': sourceId,
        'name': name,
        'type': type,
        'game': game,
        'author': author,
        'version': version,
        'tags': tags,
        'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
        'size': size,
        'downloads': downloads,
        'ratingTotal': ratingTotal,
        'ratingCount': ratingCount,
        'comments': comments,
        'sha1Hex': sha1Hex,
        'path': path,
        'headerPath': headerPath,
      }..removeWhere((_, v) => v == null);

  factory CatalogEntry.fromJson(Map<String, Object?> j) => CatalogEntry(
        sourceId: j['sourceId']! as String,
        name: j['name']! as String,
        type: j['type'] as String? ?? 'script',
        game: j['game'] as String?,
        author: j['author'] as String?,
        version: j['version'] as String?,
        tags: [for (final t in j['tags'] as List? ?? const []) '$t'],
        lastUpdated: j['lastUpdated'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['lastUpdated']! as int),
        size: j['size'] as int?,
        downloads: j['downloads'] as int?,
        ratingTotal: j['ratingTotal'] as int?,
        ratingCount: j['ratingCount'] as int?,
        comments: j['comments'] as String?,
        sha1Hex: j['sha1Hex'] as String?,
        path: j['path'] as String?,
        headerPath: j['headerPath'] as String?,
      );

  double? get rating =>
      (ratingCount ?? 0) > 0 ? ratingTotal! / ratingCount! : null;

  @override
  String toString() => '$sourceId:$name';
}

/// Extra information fetched on demand for a single entry.
class EntryDetails {
  EntryDetails({required this.text, this.versions = const []});

  /// Script header / description text.
  final String text;

  /// Older versions available for download (Lich repo only).
  final List<String> versions;
}
