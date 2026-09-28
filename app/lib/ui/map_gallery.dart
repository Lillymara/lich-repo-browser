import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:repo_core/repo_core.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import 'browse_page.dart';
import 'detail_view.dart';

/// Thumbnail grid shown instead of the list when browsing map images.
class MapGallery extends StatelessWidget {
  const MapGallery({super.key, required this.model, required this.downloads});

  final CatalogModel model;
  final Downloads downloads;

  @override
  Widget build(BuildContext context) {
    final items = model.visible;
    if (items.isEmpty) {
      return const Center(child: Text('No map images match.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final g = items[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MapViewer(
                  groups: items,
                  initial: i,
                  model: model,
                  downloads: downloads,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MapImage(
                    entry: g.entries.first,
                    model: model,
                    // Decode thumbnails small; full maps can be several MB.
                    cacheWidth: 360,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (g.isFavorite)
                        Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber.shade600,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// An image from any source, with loading and error states.
class MapImage extends StatelessWidget {
  const MapImage({
    super.key,
    required this.entry,
    required this.model,
    this.cacheWidth,
    this.fit = BoxFit.contain,
  });

  final CatalogEntry entry;
  final CatalogModel model;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget broken(Object? err) => Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: '$err',
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      ),
    );
    return FutureBuilder(
      future: model.imageFor(entry),
      builder: (context, snap) {
        if (snap.hasError) return broken(snap.error);
        final provider = snap.data;
        if (provider == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Image(
          image: cacheWidth == null
              ? provider
              : ResizeImage(provider, width: cacheWidth, allowUpscaling: false),
          fit: fit,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, err, _) => broken(err),
        );
      },
    );
  }
}

/// Full-screen, zoomable map viewer. Swipe or use ←/→ to move between maps.
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.groups,
    required this.initial,
    required this.model,
    required this.downloads,
  });

  final List<ScriptGroup> groups;
  final int initial;
  final CatalogModel model;
  final Downloads downloads;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  ScriptGroup get _current => widget.groups[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.groups.length - 1);
    if (next != _index) {
      _pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _current;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${g.name}  (${_index + 1}/${widget.groups.length})'),
            actions: [
              FavoriteButton(group: g, model: widget.model),
              IconButton(
                tooltip: 'Download to maps/',
                icon: const Icon(Icons.download),
                onPressed: () => downloadEntry(
                  context,
                  model: widget.model,
                  downloads: widget.downloads,
                  entry: g.entries.first,
                ),
              ),
              IconButton(
                tooltip: 'Details',
                icon: const Icon(Icons.info_outline),
                onPressed: () =>
                    openDetailPage(context, g, widget.model, widget.downloads),
              ),
            ],
          ),
          body: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: widget.groups.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: MapImage(
                      entry: widget.groups[i].entries.first,
                      model: widget.model,
                    ),
                  ),
                ),
              ),
              if (_index > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    tooltip: 'Previous (←)',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _go(-1),
                  ),
                ),
              if (_index < widget.groups.length - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    tooltip: 'Next (→)',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _go(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
