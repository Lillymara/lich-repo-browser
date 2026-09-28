import 'package:flutter/material.dart';

import '../catalog_model.dart';
import '../downloads.dart';
import '../updates_model.dart';
import 'browse_page.dart';
import 'format.dart';

/// Files from the catalogs that are already in the Lich folder, and whether
/// they need updating.
class InstalledTab extends StatefulWidget {
  const InstalledTab({
    super.key,
    required this.updates,
    required this.catalog,
    required this.downloads,
  });

  final UpdatesModel updates;
  final CatalogModel catalog;
  final Downloads downloads;

  @override
  State<InstalledTab> createState() => _InstalledTabState();
}

class _InstalledTabState extends State<InstalledTab> {
  bool _onlyAttention = true;
  final _busy = <InstalledItem>{};
  bool _updatingAll = false;

  UpdatesModel get u => widget.updates;

  Future<void> _update(InstalledItem item, {bool confirm = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (confirm) {
      final ok = await _confirm(
        'Replace ${item.group.name}?',
        'Your copy differs from ${sourceLabel(item.latest.sourceId)} and '
            "doesn't look older, so it may have been edited. It will be "
            'backed up before being replaced.',
      );
      if (!ok) return;
    }
    setState(() => _busy.add(item));
    try {
      final r = await u.update(item);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${item.group.name}'
            '${r.backup == null ? '' : '\nOld copy: ${r.backup}'}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Update of ${item.group.name} failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(item));
    }
  }

  Future<void> _updateAll() async {
    final todo = u.items
        .where((i) => i.state == UpdateState.updateAvailable)
        .toList();
    final ok = await _confirm(
      'Update ${todo.length} file${todo.length == 1 ? '' : 's'}?',
      'Current copies will be backed up to\n${u.folder?.backupRoot}\n\n'
          'Files marked "changed locally" are skipped; update those one at a '
          'time.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updatingAll = true);
    var done = 0;
    final failed = <String>[];
    for (final item in todo) {
      setState(() => _busy.add(item));
      try {
        await u.update(item);
        done++;
      } catch (_) {
        failed.add(item.group.name);
      }
      if (mounted) setState(() => _busy.remove(item));
    }
    if (mounted) setState(() => _updatingAll = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Updated $done file${done == 1 ? '' : 's'}'
          '${failed.isEmpty ? '' : '; failed: ${failed.join(', ')}'}',
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        if (u.folder == null && !u.scanning) {
          return _Empty(
            message: u.scannedAt == null
                ? 'Checking your Lich folder…'
                : 'No Lich folder found. Choose the folder that contains '
                      'scripts/ and data/.',
            action: u.scannedAt == null
                ? null
                : FilledButton(
                    onPressed: () async {
                      if (await pickFolder(widget.downloads) != null) {
                        await u.scan();
                      }
                    },
                    child: const Text('Choose Lich folder…'),
                  ),
          );
        }

        final attention = u.items.where((i) => i.canUpdate).toList();
        final shown = _onlyAttention ? attention : u.items;
        final available = u.items
            .where((i) => i.state == UpdateState.updateAvailable)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text('Needs attention (${attention.length})'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('All (${u.items.length})'),
                      ),
                    ],
                    selected: {_onlyAttention},
                    onSelectionChanged: (s) =>
                        setState(() => _onlyAttention = s.first),
                  ),
                  FilledButton.icon(
                    onPressed: available == 0 || _updatingAll || u.scanning
                        ? null
                        : _updateAll,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text('Update all ($available)'),
                  ),
                  IconButton(
                    tooltip: 'Check again',
                    onPressed: u.scanning || _updatingAll ? null : u.scan,
                    icon: const Icon(Icons.refresh),
                  ),
                  if (u.folder != null)
                    Text(u.folder!.root, style: text.bodySmall),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: u.scanning ? const LinearProgressIndicator() : null,
            ),
            if (u.progress != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(u.progress!, style: text.bodySmall),
              ),
            Expanded(
              child: shown.isEmpty && !u.scanning
                  ? _Empty(
                      message: _onlyAttention && u.items.isNotEmpty
                          ? 'Everything installed is up to date.'
                          : 'None of the files in this folder are in the '
                                'repositories.',
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _row(shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(InstalledItem item) {
    final scheme = Theme.of(context).colorScheme;
    final local = item.local.version;
    final remote = item.remoteVersion;
    final from = sourceLabel(item.latest.sourceId);
    final (icon, color, label) = switch (item.state) {
      UpdateState.upToDate => (
        Icons.check_circle_outline,
        scheme.primary,
        'Up to date${local == null ? '' : ' · v$local'}',
      ),
      UpdateState.updateAvailable => (
        Icons.arrow_circle_up,
        scheme.tertiary,
        'Update available: '
            '${local == null ? 'your copy' : 'v$local'} → '
            '${remote != null ? 'v$remote' : formatDate(item.latest.lastUpdated)}'
            ' from $from',
      ),
      UpdateState.modified => (
        Icons.edit_note,
        scheme.secondary,
        'Changed locally${local == null ? '' : ' (v$local'}'
            '${remote == null ? '' : '; $from has v$remote'}'
            '${local == null ? '' : ')'}',
      ),
      UpdateState.differs => (
        Icons.help_outline,
        scheme.secondary,
        'Differs from $from (updated ${formatDate(item.latest.lastUpdated)})',
      ),
    };

    final busy = _busy.contains(item);
    final Widget? trailing = busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : switch (item.state) {
            UpdateState.updateAvailable => FilledButton.tonal(
              onPressed: _updatingAll ? null : () => _update(item),
              child: const Text('Update'),
            ),
            UpdateState.modified || UpdateState.differs => OutlinedButton(
              onPressed: _updatingAll
                  ? null
                  : () => _update(item, confirm: true),
              child: const Text('Replace'),
            ),
            _ => null,
          };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.group.name),
      subtitle: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: () =>
          openDetailPage(context, item.group, widget.catalog, widget.downloads),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}
