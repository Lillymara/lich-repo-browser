import 'package:flutter/material.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import '../updates_model.dart';
import 'browse_page.dart';
import 'installed_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.catalog,
    required this.updates,
    required this.downloads,
  });

  final CatalogModel catalog;
  final UpdatesModel updates;
  final Downloads downloads;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _wasLoading = false;

  @override
  void initState() {
    super.initState();
    _wasLoading = widget.catalog.isLoading;
    widget.catalog.addListener(_onCatalog);
    // Scan whatever we have now (the cached catalog); rescans after refresh.
    if (widget.catalog.totalCount > 0 || !_wasLoading) widget.updates.scan();
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onCatalog);
    super.dispose();
  }

  /// Re-check installed files whenever a catalog refresh finishes.
  void _onCatalog() {
    final loading = widget.catalog.isLoading;
    if (_wasLoading && !loading) widget.updates.scan();
    _wasLoading = loading;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lich Repo Browser'),
          actions: [
            IconButton(
              tooltip: Downloads.isMobile ? 'Download folder' : 'Lich folder',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => showFolderDialog(
                context,
                widget.downloads,
                onChanged: widget.updates.scan,
              ),
            ),
            ListenableBuilder(
              listenable: widget.catalog,
              builder: (context, _) => IconButton(
                tooltip: 'Refresh catalogs',
                icon: const Icon(Icons.refresh),
                onPressed: widget.catalog.isLoading
                    ? null
                    : widget.catalog.refresh,
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Browse'),
              Tab(
                child: ListenableBuilder(
                  listenable: widget.updates,
                  builder: (context, _) {
                    final n = widget.updates.updateCount;
                    return Badge(
                      isLabelVisible: n > 0,
                      label: Text('$n'),
                      offset: const Offset(14, -4),
                      child: const Text('Installed'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            BrowseTab(model: widget.catalog, downloads: widget.downloads),
            InstalledTab(
              updates: widget.updates,
              catalog: widget.catalog,
              downloads: widget.downloads,
            ),
          ],
        ),
      ),
    );
  }
}
