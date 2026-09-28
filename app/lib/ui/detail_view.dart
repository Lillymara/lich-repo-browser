import 'package:flutter/material.dart';
import 'package:repo_core/repo_core.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import 'browse_page.dart';
import 'format.dart';

class DetailView extends StatefulWidget {
  const DetailView({
    super.key,
    required this.group,
    required this.model,
    required this.downloads,
  });

  final ScriptGroup group;
  final CatalogModel model;
  final Downloads downloads;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  String? _folder;
  final _status = <CatalogEntry, InstallStatus>{};
  final _busy = <CatalogEntry>{};

  ScriptGroup get g => widget.group;

  /// Where the description comes from: a Jinx header is a small file, while
  /// the Lich repo needs the whole script downloaded, so prefer Jinx.
  CatalogEntry get _describer =>
      g.entries.where((e) => e.headerPath != null).firstOrNull ??
      g.entries.where((e) => e.sourceId == 'lich').firstOrNull ??
      g.entries.first;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final folder = await widget.downloads.folder();
    final status = <CatalogEntry, InstallStatus>{};
    if (folder != null) {
      for (final e in g.entries) {
        status[e] = await widget.downloads.status(folder, e);
      }
    }
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _status
        ..clear()
        ..addAll(status);
    });
  }

  Future<void> _download(CatalogEntry e, {String? version}) async {
    final messenger = ScaffoldMessenger.of(context);
    var folder = _folder ?? await widget.downloads.folder();
    folder ??= await pickFolder(widget.downloads);
    if (folder == null || !mounted) return;

    if (await widget.downloads.fileFor(folder, e).exists()) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Replace ${e.name}?'),
          content: Text('A copy already exists in\n$folder'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy.add(e));
    try {
      final f = await widget.downloads.save(
        folder,
        widget.model.stateFor(e.sourceId).source,
        e,
        version: version,
      );
      messenger.showSnackBar(SnackBar(content: Text('Saved ${f.path}')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $err')));
    } finally {
      if (mounted) setState(() => _busy.remove(e));
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final facts = <(String, String)>[
      if (g.author != null) ('Author', g.author!),
      if (g.version != null) ('Version', g.version!),
      if (g.games.isNotEmpty) ('Game', g.games.join(', ').toUpperCase()),
      if (g.lastUpdated != null) ('Updated', formatDate(g.lastUpdated)),
      if (g.entries.any((e) => e.size != null))
        ('Size', formatSize(g.entries.map((e) => e.size).nonNulls.first)),
      if (g.downloads != null) ('Downloads', '${g.downloads}'),
      if (g.rating != null)
        (
          'Rating',
          '${g.rating!.toStringAsFixed(1)} / 10 '
              '(${g.ratingCount} vote${g.ratingCount == 1 ? '' : 's'})',
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SelectableText(g.name, style: text.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (final (label, value) in facts)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.labelSmall),
                  Text(value, style: text.bodyMedium),
                ],
              ),
          ],
        ),
        if (g.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in g.tags)
                ActionChip(
                  label: Text(t),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Search for "$t"',
                  onPressed: () => widget.model.setQuery(t),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Available from', style: text.titleSmall),
        const SizedBox(height: 4),
        for (final e in g.entries) _sourceRow(e),
        if (_folder != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Downloads go to $_folder', style: text.bodySmall),
          ),
        if (g.comments != null) ...[
          const SizedBox(height: 16),
          Text('Comments', style: text.titleSmall),
          const SizedBox(height: 4),
          SelectableText(g.comments!),
        ],
        const SizedBox(height: 16),
        Text('Description', style: text.titleSmall),
        const SizedBox(height: 4),
        _description(),
      ],
    );
  }

  Widget _sourceRow(CatalogEntry e) {
    final text = Theme.of(context).textTheme;
    final isLich = e.sourceId == 'lich';
    final status = _status[e];
    final statusText = switch (status) {
      InstallStatus.same => 'Installed (up to date)',
      InstallStatus.different => 'Installed (differs)',
      InstallStatus.unknown => 'Installed',
      _ => null,
    };
    final details = [
      if (e.game != null && isLich) e.game!.toUpperCase(),
      if (e.version != null) 'v${e.version}',
      if (e.lastUpdated != null) formatDate(e.lastUpdated),
      ?statusText,
    ].join('  ·  ');
    final busy = _busy.contains(e);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: SourceBadge(sourceId: e.sourceId),
        title: Text(widget.model.stateFor(e.sourceId).source.displayName),
        subtitle: details.isEmpty ? null : Text(details, style: text.bodySmall),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLich) _olderVersionsButton(e),
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download),
                    onPressed: () => _download(e),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _olderVersionsButton(CatalogEntry e) {
    return FutureBuilder(
      future: widget.model.details(e),
      builder: (context, snap) {
        final versions = snap.data?.versions ?? const <String>[];
        if (versions.isEmpty) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: 'Download an older version',
          icon: const Icon(Icons.history),
          onSelected: (v) => _download(e, version: v),
          itemBuilder: (_) => [
            for (final v in versions) PopupMenuItem(value: v, child: Text(v)),
          ],
        );
      },
    );
  }

  Widget _description() {
    final e = _describer;
    final source = widget.model.stateFor(e.sourceId).source;
    if (e.type == 'map' && source is JinxSource && e.path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: InteractiveViewer(
          child: Image.network(
            source.urlFor(e.path!).toString(),
            errorBuilder: (_, err, _) => Text('Couldn\'t load image: $err'),
          ),
        ),
      );
    }
    return FutureBuilder(
      future: widget.model.details(e),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Row(
            children: [
              Expanded(child: Text('Couldn\'t load details: ${snap.error}')),
              TextButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        final body = snap.data!.text.trim();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            body.isEmpty ? 'This file has no header comment.' : body,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        );
      },
    );
  }
}
