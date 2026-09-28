import 'package:flutter/material.dart';
import 'package:repo_core/repo_core.dart';

import '../catalog_model.dart';
import 'format.dart';

/// Lists every source with an on/off switch, and lets the user add or
/// remove their own Jinx repos.
Future<void> showSourcesDialog(BuildContext context, CatalogModel model) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: model,
        builder: (ctx, _) => AlertDialog(
          title: const Text('Sources'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in model.sources)
                  SwitchListTile(
                    value: s.enabled,
                    onChanged: (v) => model.setSourceEnabled(s, v),
                    title: Text(s.source.displayName),
                    subtitle: Text(_describe(s, model)),
                    secondary: model.isCustom(s)
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmRemove(ctx, model, s),
                          )
                        : const SizedBox(width: 40),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _showAddRepo(ctx, model),
              icon: const Icon(Icons.add),
              label: const Text('Add Jinx repository…'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );

String _describe(SourceState s, CatalogModel model) {
  final parts = [
    if (s.source case JinxSource(:final baseUrl)) baseUrl,
    if (s.entries.isNotEmpty) '${s.entries.length} files',
    if (s.fetchedAt != null) 'fetched ${formatDate(s.fetchedAt)}',
    if (s.state == LoadState.error) 'error: ${s.error}',
    if (model.archiveIds.contains(s.source.id)) 'archive',
    if (model.isCustom(s)) 'added by you',
  ];
  return parts.join(' · ');
}

Future<void> _confirmRemove(
  BuildContext context,
  CatalogModel model,
  SourceState s,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Remove ${s.source.displayName}?'),
      content: const Text(
        'Files you already downloaded from it stay where they are.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (ok == true) await model.removeSource(s);
}

Future<void> _showAddRepo(BuildContext context, CatalogModel model) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AddRepoDialog(model: model),
    );

class _AddRepoDialog extends StatefulWidget {
  const _AddRepoDialog({required this.model});

  final CatalogModel model;

  @override
  State<_AddRepoDialog> createState() => _AddRepoDialogState();
}

class _AddRepoDialogState extends State<_AddRepoDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;
  String? _checked;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _validate() {
    final name = _name.text.trim();
    final url = CatalogModel.normalizeRepoUrl(_url.text);
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(name)) {
      return 'Name: lower-case letters, digits, - and _ only';
    }
    if (widget.model.sources.any((s) => s.source.id == 'jinx:$name')) {
      return 'There is already a source called "$name"';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'URL must start with https://';
    }
    return null;
  }

  Future<void> _add() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _checked = null;
    });
    try {
      final count = await CatalogModel.probeJinx(_url.text);
      setState(() => _checked = 'Found $count files. Adding…');
      await widget.model.addJinxRepo(_name.text.trim(), _url.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = "Couldn't read a Jinx manifest there: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add a Jinx repository'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Short name',
                hintText: 'e.g. my-scripts',
              ),
            ),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.github.io/my-repo',
                helperText: 'The folder that contains manifest.json',
              ),
              onSubmitted: (_) => _busy ? null : _add(),
            ),
            const SizedBox(height: 12),
            Text(
              'Only add repositories you trust. Scripts run inside Lich with '
              'full access to your computer.',
              style: TextStyle(color: scheme.tertiary),
            ),
            if (_checked != null) ...[
              const SizedBox(height: 8),
              Text(_checked!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: Text(_busy ? 'Checking…' : 'Add'),
        ),
      ],
    );
  }
}
