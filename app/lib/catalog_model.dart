import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:repo_core/repo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_query.dart';

enum LoadState { idle, loading, ready, error }

/// A source plus its load status and whether the user has it switched on.
class SourceState {
  SourceState(this.source, {this.enabled = true});

  final RepoSource source;
  bool enabled;
  LoadState state = LoadState.idle;
  List<CatalogEntry> entries = const [];
  String? error;

  /// When [entries] were fetched from the network.
  DateTime? fetchedAt;

  /// True while [entries] come from the on-disk cache rather than a fetch
  /// made this session (e.g. still refreshing, or offline).
  bool fromCache = false;
}

/// The same file (by name) as offered by one or more sources.
class ScriptGroup {
  ScriptGroup(this.name, this.entries);

  final String name;
  final List<CatalogEntry> entries;

  CatalogEntry? get _lich =>
      entries.where((e) => e.sourceId == 'lich').firstOrNull;

  String get type => entries.first.type;

  Set<String> get games => {
    for (final e in entries)
      if (e.game != null) e.game!,
  };

  String? get author =>
      entries.map((e) => e.author).whereType<String>().firstOrNull;

  /// Newest version any source advertises (only Jinx publishes versions).
  String? get version {
    final vs = entries.map((e) => e.version).whereType<String>();
    return vs.isEmpty ? null : sortVersionsDesc(vs).first;
  }

  DateTime? get lastUpdated => entries
      .map((e) => e.lastUpdated)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  int? get downloads => _lich?.downloads;
  double? get rating => _lich?.rating;
  int? get ratingCount => _lich?.ratingCount;
  String? get comments => _lich?.comments;

  List<String> get tags {
    final seen = <String>{};
    return [
      for (final e in entries)
        for (final t in e.tags)
          if (seen.add(t.toLowerCase())) t,
    ];
  }

  /// Lowercased text the search box matches against.
  late final String searchText = [
    name,
    author ?? '',
    ...tags,
    comments ?? '',
  ].join('\n').toLowerCase();
}

enum SortBy { name, updated, downloads, rating }

enum TypeFilter { scripts, data, maps, all }

enum GameFilter { all, gs, dr }

/// Holds every source's catalog and the current search/filter/sort.
class CatalogModel extends ChangeNotifier {
  CatalogModel({List<RepoSource>? sources, this.prefs, this.cacheDir})
    : sources = [
        for (final s in sources ?? [LichRepoSource(), ...JinxSource.defaults()])
          SourceState(s),
      ] {
    _restore();
  }

  final List<SourceState> sources;
  final SharedPreferences? prefs;

  /// Where each source's last catalog is kept for fast, offline startup.
  final Directory? cacheDir;

  String _query = '';
  SearchQuery _parsed = SearchQuery.parse('');
  SortBy _sortBy = SortBy.name;
  TypeFilter _typeFilter = TypeFilter.scripts;
  GameFilter _gameFilter = GameFilter.all;
  String? _selectedName;

  List<ScriptGroup> _groups = const [];
  List<ScriptGroup>? _visible;

  String get query => _query;

  /// Set when part of the search was ignored (e.g. a missing `)`).
  String? get queryWarning => _parsed.warning;
  SortBy get sortBy => _sortBy;
  TypeFilter get typeFilter => _typeFilter;
  GameFilter get gameFilter => _gameFilter;

  bool get isLoading => sources.any((s) => s.state == LoadState.loading);
  int get totalCount => _groups.length;

  /// Every group from enabled sources, ignoring search and filters.
  List<ScriptGroup> get allGroups => _groups;

  ScriptGroup? get selected =>
      _groups.where((g) => g.name == _selectedName).firstOrNull;

  SourceState stateFor(String sourceId) =>
      sources.firstWhere((s) => s.source.id == sourceId);

  /// Loads every enabled source in parallel, updating the UI as each lands.
  Future<void> refresh() async {
    await Future.wait([
      for (final s in sources)
        if (s.enabled) _load(s),
    ]);
  }

  Future<void> _load(SourceState s) async {
    s
      ..state = LoadState.loading
      ..error = null;
    notifyListeners();
    try {
      s
        ..entries = await s.source.fetchCatalog()
        ..fetchedAt = DateTime.now()
        ..fromCache = false
        ..state = LoadState.ready;
      unawaited(_writeCache(s));
    } catch (e) {
      // Keep whatever we had (e.g. from the cache) so the app works offline.
      s
        ..state = LoadState.error
        ..error = '$e';
    }
    _regroup();
  }

  File? _cacheFile(SourceState s) => cacheDir == null
      ? null
      : File(
          '${cacheDir!.path}${Platform.pathSeparator}'
          'catalog-${s.source.id.replaceAll(RegExp(r'[^\w-]'), '_')}.json',
        );

  /// Fills every source from its cached catalog, if there is one.
  Future<void> loadCached() async {
    for (final s in sources) {
      final f = _cacheFile(s);
      if (f == null || !await f.exists()) continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, Object?>;
        s
          ..entries = [
            for (final e in j['entries']! as List)
              CatalogEntry.fromJson(e as Map<String, Object?>),
          ]
          ..fetchedAt = DateTime.fromMillisecondsSinceEpoch(
            j['fetchedAt']! as int,
          )
          ..fromCache = true;
      } catch (_) {
        // A corrupt cache just means a slower start.
      }
    }
    _regroup();
  }

  Future<void> _writeCache(SourceState s) async {
    final f = _cacheFile(s);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'fetchedAt': s.fetchedAt!.millisecondsSinceEpoch,
          'entries': [for (final e in s.entries) e.toJson()],
        }),
      );
      await tmp.rename(f.path);
    } catch (_) {
      // Caching is best-effort.
    }
  }

  void setQuery(String q) {
    _query = q;
    _parsed = SearchQuery.parse(q);
    _invalidate();
  }

  void setSortBy(SortBy v) {
    _sortBy = v;
    prefs?.setString('sortBy', v.name);
    _invalidate();
  }

  void setTypeFilter(TypeFilter v) {
    _typeFilter = v;
    prefs?.setString('typeFilter', v.name);
    _invalidate();
  }

  void setGameFilter(GameFilter v) {
    _gameFilter = v;
    prefs?.setString('gameFilter', v.name);
    _invalidate();
  }

  void setSourceEnabled(SourceState s, bool enabled) {
    s.enabled = enabled;
    prefs?.setStringList('disabledSources', [
      for (final x in sources)
        if (!x.enabled) x.source.id,
    ]);
    if (enabled && s.state == LoadState.idle) {
      _load(s);
    } else {
      _regroup();
    }
  }

  final _details = <String, Future<EntryDetails>>{};

  /// Header text / versions for [e], fetched once and cached (failures are
  /// dropped from the cache so they can be retried).
  Future<EntryDetails> details(CatalogEntry e) {
    final key = '$e\u0000${e.game}';
    return _details.putIfAbsent(key, () {
      final f = stateFor(e.sourceId).source.fetchDetails(e);
      f.then(
        (_) {},
        onError: (Object _) {
          _details.remove(key);
        },
      );
      return f;
    });
  }

  void select(ScriptGroup? g) {
    _selectedName = g?.name;
    notifyListeners();
  }

  /// Groups after search, filters and sort. Cached until something changes.
  List<ScriptGroup> get visible => _visible ??= _computeVisible();

  List<ScriptGroup> _computeVisible() {
    bool typeOk(ScriptGroup g) => switch (_typeFilter) {
      TypeFilter.all => true,
      TypeFilter.scripts => g.type == 'script',
      TypeFilter.data => g.type == 'data' || g.type == 'engine',
      TypeFilter.maps => g.type == 'map',
    };
    bool gameOk(ScriptGroup g) {
      if (_gameFilter == GameFilter.all) return true;
      final games = g.games;
      return games.isEmpty ||
          games.contains('any') ||
          games.contains(_gameFilter.name);
    }

    final out = [
      for (final g in _groups)
        if (typeOk(g) && gameOk(g) && _parsed.matches(g)) g,
    ];
    int byName(ScriptGroup a, ScriptGroup b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int desc<T extends Comparable<Object>>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    out.sort(switch (_sortBy) {
      SortBy.name => byName,
      SortBy.updated => (a, b) => desc(a.lastUpdated, b.lastUpdated),
      SortBy.downloads => (a, b) => desc(a.downloads, b.downloads),
      SortBy.rating => (a, b) {
        final r = desc(a.rating, b.rating);
        return r != 0 ? r : desc(a.ratingCount, b.ratingCount);
      },
    });
    return out;
  }

  void _regroup() {
    final byName = <String, List<CatalogEntry>>{};
    for (final s in sources) {
      if (!s.enabled) continue;
      for (final e in s.entries) {
        byName.putIfAbsent(e.name.toLowerCase(), () => []).add(e);
      }
    }
    _groups = [
      for (final list in byName.values) ScriptGroup(list.first.name, list),
    ];
    _invalidate();
  }

  void _invalidate() {
    _visible = null;
    notifyListeners();
  }

  void _restore() {
    final p = prefs;
    if (p == null) return;
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == p.getString(key)).firstOrNull ?? fallback;
    _sortBy = pick(SortBy.values, 'sortBy', _sortBy);
    _typeFilter = pick(TypeFilter.values, 'typeFilter', _typeFilter);
    _gameFilter = pick(GameFilter.values, 'gameFilter', _gameFilter);
    final disabled = p.getStringList('disabledSources') ?? const [];
    for (final s in sources) {
      s.enabled = !disabled.contains(s.source.id);
    }
  }
}
