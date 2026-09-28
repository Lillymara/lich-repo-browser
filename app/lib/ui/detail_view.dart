import 'package:flutter/material.dart';
import 'package:repo_core/repo_core.dart';
import 'package:share_plus/share_plus.dart';

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
  LichFolder? _folder;
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
    try {
      await downloadEntry(
        context,
        model: widget.model,
        downloads: widget.downloads,
        entry: e,
        version: version,
        onStart: () => setState(() => _busy.add(e)),
      );
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
        Row(
          children: [
            Expanded(child: SelectableText(g.name, style: text.headlineSmall)),
            FavoriteButton(group: g, model: widget.model),
          ],
        ),
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
                  tooltip: 'Search for tag "$t"',
                  onPressed: () => widget.model.setQuery('tag:"$t"'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Available from', style: text.titleSmall),
        const SizedBox(height: 4),
        for (final e in g.entries) _sourceRow(e),
        if (g.entries.where((e) => e.sourceId == 'lich').firstOrNull
            case final lich?)
          _RatingRow(entry: lich, model: widget.model),
        if (_folder != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _folder!.flat
                  ? 'Downloads are saved in the app and offered to share.'
                  : 'Downloads go to ${_folder!.dirFor(_describer)}',
              style: text.bodySmall,
            ),
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

/// Opens the system share sheet for [path] (phones: save to Files, send to
/// another app, etc.).
Future<void> shareFile(BuildContext context, String path) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      // Needed on iPad, where the sheet is a popover.
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Downloads [entry] into the Lich folder (asking for it if unset), after
/// confirming replacements and engine files. On phones the saved file is
/// offered to the share sheet. [onStart] runs once the download begins.
Future<void> downloadEntry(
  BuildContext context, {
  required CatalogModel model,
  required Downloads downloads,
  required CatalogEntry entry,
  String? version,
  VoidCallback? onStart,
}) async {
  final e = entry;
  final messenger = ScaffoldMessenger.of(context);
  var folder = await downloads.folder();
  if (folder == null && await pickFolder(downloads) != null) {
    folder = await downloads.folder();
  }
  if (folder == null || !context.mounted) return;

  final target = folder.fileFor(e);
  final exists = !folder.flat && await target.exists();
  String? warning;
  if (e.type == 'engine') {
    warning =
        '${e.name} is part of Lich itself and goes in\n'
        '${folder.dirFor(e)}\n\nOnly continue if you know you need it.';
  } else if (exists) {
    warning =
        'A copy already exists in\n${target.parent.path}\n\n'
        'The current file will be backed up first.';
  }
  if (warning != null) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(exists ? 'Replace ${e.name}?' : 'Download ${e.name}?'),
        content: Text(warning!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(exists ? 'Replace' : 'Download'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }

  onStart?.call();
  try {
    final r = await downloads.save(
      folder,
      model.stateFor(e.sourceId).source,
      e,
      version: version,
    );
    if (folder.flat && context.mounted) {
      await shareFile(context, r.file.path);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.backup == null
                ? 'Saved ${r.file.path}'
                : 'Saved ${r.file.path}\nOld copy: ${r.backup}',
          ),
        ),
      );
    }
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('Download failed: $err')));
  }
}

/// Star toggle for favorites; listens to the model so it stays in sync.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.group, required this.model});

  final ScriptGroup group;
  final CatalogModel model;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final fav = group.isFavorite;
      return IconButton(
        tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
        icon: Icon(
          fav ? Icons.star : Icons.star_border,
          color: fav ? Colors.amber.shade600 : null,
        ),
        onPressed: () => model.toggleFavorite(group),
      );
    },
  );
}

/// Lets the user rate a Lich repo script 1–10 (like `;repository rate`).
class _RatingRow extends StatefulWidget {
  const _RatingRow({required this.entry, required this.model});

  final CatalogEntry entry;
  final CatalogModel model;

  @override
  State<_RatingRow> createState() => _RatingRowState();
}

class _RatingRowState extends State<_RatingRow> {
  late double _value = (widget.model.myRating(widget.entry) ?? 8).toDouble();
  bool _sending = false;

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await widget.model.rate(widget.entry, _value.round());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Thanks! You rated ${widget.entry.name} ${_value.round()}/10. '
            'The average updates on the next refresh.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Rating failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mine = widget.model.myRating(widget.entry);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            mine == null ? 'Rate on the Lich repository' : 'You rated $mine/10',
            style: text.bodyMedium,
          ),
          SizedBox(
            width: 220,
            child: Slider(
              value: _value,
              min: 1,
              max: 10,
              divisions: 9,
              label: '${_value.round()}',
              onChanged: _sending ? null : (v) => setState(() => _value = v),
            ),
          ),
          FilledButton.tonal(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending…' : 'Rate ${_value.round()}'),
          ),
        ],
      ),
    );
  }
}
