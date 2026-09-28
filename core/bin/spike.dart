// Phase-1 spike: exercise both sources from the command line.
//
//   dart run bin/spike.dart list [search] [--source lich|jinx|all]
//   dart run bin/spike.dart info <file> [--source ...]
//   dart run bin/spike.dart download <file> [--source ...] [--out dir]
import 'dart:io';

import 'package:repo_core/repo_core.dart';

Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? opt(String name) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) return null;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  final which = opt('source') ?? 'all';
  final outDir = opt('out') ?? '.';
  if (args.isEmpty) {
    stderr.writeln('usage: spike.dart list|info|download [name] '
        '[--source lich|jinx|all] [--out dir]');
    exit(64);
  }
  final command = args.removeAt(0);
  final query = args.isEmpty ? null : args.first.toLowerCase();

  final sources = <RepoSource>[
    if (which == 'all' || which == 'lich') LichRepoSource(),
    if (which == 'all' || which == 'jinx') ...JinxSource.defaults(),
  ];

  // Fetch every catalog in parallel; one failing source shouldn't sink the rest.
  final entries = <CatalogEntry>[];
  final bySource = {for (final s in sources) s.id: s};
  await Future.wait(sources.map((s) async {
    final sw = Stopwatch()..start();
    try {
      final list = await s.fetchCatalog();
      entries.addAll(list);
      stderr.writeln('${s.displayName}: ${list.length} entries '
          '(${sw.elapsedMilliseconds} ms)');
    } catch (e) {
      stderr.writeln('${s.displayName}: FAILED - $e');
    }
  }));

  final matches = query == null
      ? entries
      : entries.where((e) => e.name.toLowerCase().contains(query)).toList();

  switch (command) {
    case 'list':
      matches.sort((a, b) => a.name.compareTo(b.name));
      _printTable(matches);
    case 'info':
    case 'download':
      final exact = matches.where((e) => e.name.toLowerCase() == query);
      final pick = (exact.isNotEmpty ? exact : matches).toList();
      if (pick.isEmpty) {
        stderr.writeln('no match for "$query"');
        exit(1);
      }
      final entry = pick.first;
      if (pick.length > 1) {
        stderr.writeln('${pick.length} matches, using ${entry.sourceId}:'
            '${entry.name} (${pick.map((e) => e.sourceId).toSet().join(', ')})');
      }
      final source = bySource[entry.sourceId]!;
      if (command == 'info') {
        final d = await source.fetchDetails(entry);
        _printTable([entry]);
        if (entry.comments != null) print('\ncomments: ${entry.comments}');
        if (d.versions.isNotEmpty) {
          print('versions (${d.versions.length}): '
              '${d.versions.take(10).join(', ')}'
              '${d.versions.length > 10 ? ', …' : ''}');
        }
        print('\n${d.text}');
      } else {
        final bytes = await source.download(entry);
        final file = File('$outDir/${entry.name}');
        await file.writeAsBytes(bytes);
        print('saved ${bytes.length} bytes to ${file.path}');
      }
    default:
      stderr.writeln('unknown command $command');
      exit(64);
  }
}

void _printTable(List<CatalogEntry> rows) {
  String d(DateTime? t) =>
      t == null ? '' : t.toIso8601String().substring(0, 10);
  String c(Object? v, int w) {
    final s = v?.toString() ?? '';
    return s.length > w ? '${s.substring(0, w - 1)}…' : s.padRight(w);
  }

  print('${c('source', 22)} ${c('file', 28)} ${c('game', 5)} ${c('type', 6)} '
      '${c('version', 9)} ${c('updated', 10)} ${c('author', 18)} '
      '${c('DLs', 6)} ${c('rating', 9)} tags');
  for (final e in rows) {
    final rating = e.rating == null
        ? ''
        : '${e.rating!.toStringAsFixed(1)} (${e.ratingCount})';
    print('${c(e.sourceId, 22)} ${c(e.name, 28)} ${c(e.game, 5)} '
        '${c(e.type, 6)} ${c(e.version, 9)} ${c(d(e.lastUpdated), 10)} '
        '${c(e.author, 18)} ${c(e.downloads, 6)} ${c(rating, 9)} '
        '${e.tags.take(4).join(',')}');
  }
  print('(${rows.length} rows)');
}
