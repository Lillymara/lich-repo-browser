import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import '../search_query.dart';
import 'detail_view.dart';
import 'format.dart';
import 'map_gallery.dart';

/// Wide screens show list + detail side by side; narrow ones push a page.
const wideBreakpoint = 900.0;

/// The Browse tab: filters, the result list and (on wide screens) details.
class BrowseTab extends StatelessWidget {
  const BrowseTab({super.key, required this.model, required this.downloads});

  final CatalogModel model;
  final Downloads downloads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
        if (model.typeFilter == TypeFilter.maps) {
          return Column(
            children: [
              _FilterBar(model: model, wide: wide),
              SizedBox(
                height: 2,
                child: model.isLoading ? const LinearProgressIndicator() : null,
              ),
              Expanded(
                child: MapGallery(model: model, downloads: downloads),
              ),
            ],
          );
        }
        final list = _ResultList(
          model: model,
          onOpen: (g) {
            model.select(g);
            if (!wide) openDetailPage(context, g, model, downloads);
          },
        );
        final selected = model.selected;
        return Column(
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
        );
      },
    );
  }
}

/// Shows [g]'s details as a full page (narrow screens, Installed tab).
void openDetailPage(
  BuildContext context,
  ScriptGroup g,
  CatalogModel model,
  Downloads downloads,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(g.name)),
        body: DetailView(group: g, model: model, downloads: downloads),
      ),
    ),
  );
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
    // Keep the box in sync when the query is set elsewhere (tag chips).
    if (_search.text != m.query) {
      _search.value = TextEditingValue(
        text: m.query,
        selection: TextSelection.collapsed(offset: m.query.length),
      );
    }
    final searchField = SizedBox(
      width: widget.wide ? 420 : double.infinity,
      child: TextField(
        controller: _search,
        onChanged: m.setQuery,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search… e.g. bounty OR bigshot -mirror',
          isDense: true,
          border: const OutlineInputBorder(),
          helperText: m.queryWarning,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_search.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    m.setQuery('');
                  },
                ),
              IconButton(
                tooltip: 'Search syntax',
                icon: const Icon(Icons.help_outline),
                onPressed: () => _showSearchHelp(context),
              ),
            ],
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
              _Menu<ShowOnly>(
                icon: Icons.filter_list,
                value: m.showOnly,
                labels: {
                  ShowOnly.all: 'Show all',
                  ShowOnly.favorites: 'Favorites (${m.countFlag('favorite')})',
                  ShowOnly.fresh: m.since == null
                      ? 'New & updated (after your next visit)'
                      : 'New & updated since ${formatDate(m.since)} '
                            '(${m.countFlag('new') + m.countFlag('updated')})',
                  ShowOnly.installed: 'Installed (${m.countFlag('installed')})',
                  ShowOnly.outdated:
                      'Updates available (${m.countFlag('outdated')})',
                },
                onChanged: m.setShowOnly,
              ),
              if (m.showOnly == ShowOnly.fresh && m.since != null)
                TextButton.icon(
                  onPressed: m.markAllSeen,
                  icon: const Icon(Icons.done_all),
                  label: const Text('Mark all as seen'),
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
    final scheme = Theme.of(context).colorScheme;
    final hasData = s.entries.isNotEmpty;
    final Widget? status = switch (s.state) {
      LoadState.loading => const SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      LoadState.error => Icon(
        hasData ? Icons.cloud_off : Icons.error_outline,
        size: 18,
        color: hasData ? scheme.tertiary : scheme.error,
      ),
      _ => null,
    };
    final count = hasData ? ' (${s.entries.length})' : '';
    final asOf = s.fetchedAt == null ? '' : ' from ${formatDate(s.fetchedAt)}';
    final tooltip = switch (s.state) {
      LoadState.error when hasData =>
        'Offline: showing the saved list$asOf\n${s.error}',
      LoadState.error => s.error!,
      LoadState.loading when hasData => 'Refreshing (showing saved list$asOf)',
      _ => s.source.displayName,
    };
    return Tooltip(
      message: tooltip,
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
          model: model,
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
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final ScriptGroup group;
  final CatalogModel model;
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

    final scheme = theme.colorScheme;
    final flags = g.flags;
    final fav = g.isFavorite;
    return ListTile(
      selected: selected,
      onTap: onTap,
      contentPadding: const EdgeInsetsDirectional.only(start: 4, end: 16),
      leading: IconButton(
        tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
        icon: Icon(
          fav ? Icons.star : Icons.star_border,
          color: fav ? Colors.amber.shade600 : scheme.outline,
        ),
        onPressed: () => model.toggleFavorite(g),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: g.name),
            if (g.version != null)
              TextSpan(text: '  v${g.version}', style: muted),
            if (flags.contains('new'))
              _badge(' NEW ', scheme.primary, scheme.onPrimary),
            if (flags.contains('updated'))
              _badge(' UPDATED ', scheme.secondary, scheme.onSecondary),
            if (flags.contains('outdated'))
              _badge(' UPDATE AVAILABLE ', scheme.tertiary, scheme.onTertiary)
            else if (flags.contains('installed'))
              _badge(
                ' INSTALLED ',
                scheme.surfaceContainerHighest,
                scheme.onSurfaceVariant,
              ),
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

InlineSpan _badge(String text, Color bg, Color fg) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Container(
    margin: const EdgeInsets.only(left: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
    ),
  ),
);

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

/// Shows the current Lich folder and lets the user pick another.
Future<void> showFolderDialog(
  BuildContext context,
  Downloads downloads, {
  VoidCallback? onChanged,
}) async {
  final current = await downloads.folder();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(Downloads.isMobile ? 'Download folder' : 'Lich folder'),
      content: SelectableText(
        current == null
            ? 'No Lich install found. Choose your Lich folder (the one '
                  'containing scripts/ and data/).'
            : Downloads.isMobile
            ? 'Downloads are saved in the app, then offered to share or '
                  'save elsewhere.\n\n${current.root}'
            : '${current.root}\n\nScripts go to scripts/, data files to '
                  'data/, map images to maps/.',
      ),
      actions: [
        if (!Downloads.isMobile)
          TextButton(
            onPressed: () async {
              final picked = await pickFolder(
                downloads,
                initial: current?.root,
              );
              if (picked != null) {
                onChanged?.call();
                if (ctx.mounted) Navigator.pop(ctx);
              }
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

/// Asks for the Lich folder; picking its scripts/ folder is accepted too.
Future<String?> pickFolder(Downloads downloads, {String? initial}) async {
  final picked = await getDirectoryPath(
    initialDirectory: initial,
    confirmButtonText: 'Use this folder',
  );
  if (picked != null) await downloads.setRoot(picked);
  return picked;
}

void _showSearchHelp(BuildContext context) {
  final mono = Theme.of(context).textTheme.bodyMedium
      ?.copyWith(fontFamily: 'monospace');
  Widget row(String code, String what) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 210, child: SelectableText(code, style: mono)),
        Expanded(child: Text(what)),
      ],
    ),
  );
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Search syntax'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('bigshot hunting', 'both words (AND is implied)'),
              row('bounty OR bigshot', 'either (also |)'),
              row('NOT mirror  -mirror', 'exclude (also !)'),
              row('(bounty OR gems) -dr', 'group with parentheses'),
              row('"boost bounty"', 'exact phrase'),
              row('bigshot AND hunting', 'explicit AND (also &)'),
              row(
                'name:big*  name:*.xml',
                '* and ? wildcards match the '
                    'whole field',
              ),
              const Divider(),
              Text('Fields', style: Theme.of(ctx).textTheme.titleSmall),
              for (final e in SearchQuery.fields.entries)
                row('${e.key}:', e.value),
              const Divider(),
              row('author:tysong tag:bounty', ''),
              row('downloads:>500 rating:>=8', ''),
              row('age:<90d -source:mirror', 'updated in the last 90 days'),
              row('updated:>=2026-01-01', ''),
              const SizedBox(height: 8),
              const Text(
                'Operators must be upper case, so and/or/not '
                'search as ordinary words. Without a field, words match '
                'the name, author, tags and comments.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
