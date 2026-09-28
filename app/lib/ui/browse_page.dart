import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import 'detail_view.dart';
import 'format.dart';

/// Wide screens show list + detail side by side; narrow ones push a page.
const _wideBreakpoint = 900.0;

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key, required this.model, required this.downloads});

  final CatalogModel model;
  final Downloads downloads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
        final list = _ResultList(
          model: model,
          onOpen: (g) {
            model.select(g);
            if (!wide) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(g.name)),
                    body: DetailView(
                      group: g,
                      model: model,
                      downloads: downloads,
                    ),
                  ),
                ),
              );
            }
          },
        );
        final selected = model.selected;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Lich Repo Browser'),
            actions: [
              IconButton(
                tooltip: 'Download folder',
                icon: const Icon(Icons.folder_outlined),
                onPressed: () => showFolderDialog(context, downloads),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: model.isLoading ? null : model.refresh,
              ),
            ],
          ),
          body: Column(
            children: [
              _FilterBar(model: model, wide: wide),
              SizedBox(
                height: 2,
                child: model.isLoading ? const LinearProgressIndicator() : null,
              ),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: list),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 4,
                            child: selected == null
                                ? const _Placeholder()
                                : DetailView(
                                    key: ValueKey(selected.name),
                                    group: selected,
                                    model: model,
                                    downloads: downloads,
                                  ),
                          ),
                        ],
                      )
                    : list,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatefulWidget {
  const _FilterBar({required this.model, required this.wide});

  final CatalogModel model;
  final bool wide;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  late final _search = TextEditingController(text: widget.model.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final searchField = SizedBox(
      width: widget.wide ? 320 : double.infinity,
      child: TextField(
        controller: _search,
        onChanged: m.setQuery,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search name, author, tags…',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    m.setQuery('');
                  },
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              searchField,
              SegmentedButton<GameFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: GameFilter.all, label: Text('All')),
                  ButtonSegment(value: GameFilter.gs, label: Text('GS')),
                  ButtonSegment(value: GameFilter.dr, label: Text('DR')),
                ],
                selected: {m.gameFilter},
                onSelectionChanged: (s) => m.setGameFilter(s.first),
              ),
              _Menu<TypeFilter>(
                icon: Icons.category_outlined,
                value: m.typeFilter,
                labels: const {
                  TypeFilter.scripts: 'Scripts',
                  TypeFilter.data: 'Data files',
                  TypeFilter.maps: 'Map images',
                  TypeFilter.all: 'Everything',
                },
                onChanged: m.setTypeFilter,
              ),
              _Menu<SortBy>(
                icon: Icons.sort,
                value: m.sortBy,
                labels: const {
                  SortBy.name: 'Name',
                  SortBy.updated: 'Recently updated',
                  SortBy.downloads: 'Most downloaded',
                  SortBy.rating: 'Highest rated',
                },
                onChanged: m.setSortBy,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in m.sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _SourceChip(
                      state: s,
                      onChanged: (v) => m.setSourceEnabled(s, v),
                    ),
                  ),
                Text(
                  '${m.visible.length} of ${m.totalCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({
    required this.icon,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Chip(avatar: Icon(icon, size: 18), label: Text(labels[value]!)),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.state, required this.onChanged});

  final SourceState state;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final Widget? status = switch (s.state) {
      LoadState.loading => const SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      LoadState.error => Icon(
        Icons.error_outline,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      ),
      _ => null,
    };
    final count = s.state == LoadState.ready ? ' (${s.entries.length})' : '';
    return Tooltip(
      message: s.error ?? s.source.displayName,
      child: FilterChip(
        avatar: status,
        label: Text('${sourceLabel(s.source.id)}$count'),
        selected: s.enabled,
        onSelected: onChanged,
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.model, required this.onOpen});

  final CatalogModel model;
  final ValueChanged<ScriptGroup> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = model.visible;
    if (items.isEmpty) {
      final allFailed = model.sources
          .where((s) => s.enabled)
          .every((s) => s.state == LoadState.error);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            model.isLoading
                ? 'Loading catalogs…'
                : allFailed
                ? 'Couldn\'t reach any repository. Check your connection '
                      'and press refresh.'
                : 'No matches.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final selected = model.selected?.name;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final g = items[i];
        return _ResultTile(
          group: g,
          selected: g.name == selected,
          onTap: () => onOpen(g),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final ScriptGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final subtitle = [
      if (g.author != null) g.author!,
      if (g.lastUpdated != null) formatDate(g.lastUpdated),
      if (g.tags.isNotEmpty) g.tags.take(4).join(', '),
    ].join('  ·  ');
    final stats = [
      if (g.rating != null) '★ ${g.rating!.toStringAsFixed(1)}',
      if (g.downloads != null) '⇩ ${formatCount(g.downloads!)}',
    ].join('   ');

    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: g.name),
            if (g.version != null)
              TextSpan(text: '  v${g.version}', style: muted),
          ],
        ),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (stats.isNotEmpty) Text(stats, style: muted),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in {for (final e in g.entries) e.sourceId})
                SourceBadge(sourceId: id),
            ],
          ),
        ],
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lich = sourceId == 'lich';
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: lich ? scheme.primaryContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        sourceLabel(sourceId),
        style: TextStyle(
          fontSize: 11,
          color: lich ? scheme.onPrimaryContainer : scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'Select a script to see its details',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

/// Shows the current download folder and lets the user pick another.
Future<void> showFolderDialog(BuildContext context, Downloads downloads) async {
  final current = await downloads.folder();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Download folder'),
      content: SelectableText(
        current ??
            'No Lich scripts folder found. Choose where downloads should go.',
      ),
      actions: [
        if (!Downloads.isMobile)
          TextButton(
            onPressed: () async {
              final picked = await pickFolder(downloads, initial: current);
              if (picked != null && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Change…'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<String?> pickFolder(Downloads downloads, {String? initial}) async {
  final picked = await getDirectoryPath(
    initialDirectory: initial,
    confirmButtonText: 'Use this folder',
  );
  if (picked != null) await downloads.setFolder(picked);
  return picked;
}
