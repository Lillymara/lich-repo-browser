/// Pulls the leading documentation block out of a Lich script: either a
/// `=begin ... =end` block or a run of `#` comment lines at the top of the
/// file. Returns an empty string if neither is present.
String extractScriptHeader(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length) return '';

  if (lines[i].startsWith('=begin')) {
    final end = lines.indexWhere((l) => l.startsWith('=end'), i + 1);
    return lines
        .sublist(i + 1, end < 0 ? lines.length : end)
        .join('\n')
        .trimRight();
  }

  final out = <String>[];
  for (; i < lines.length && lines[i].trimLeft().startsWith('#'); i++) {
    out.add(lines[i].trimLeft().replaceFirst(RegExp(r'^#+ ?'), ''));
  }
  return out.join('\n').trimRight();
}

/// The `version:` value from a script's header, if it has one.
String? parseScriptVersion(String header) => RegExp(
      r'^[ \t#]*version\s*:\s*v?([0-9][\w.\-]*)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(header)?.group(1);

/// Compares version strings by their numeric parts, so 4.12.11 > 4.12.9.
/// Returns <0 if [a] is older than [b], 0 if equal, >0 if newer.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.split(RegExp(r'[^0-9]+')))
          if (p.isNotEmpty) int.parse(p)
      ];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Orders version strings newest first (see [compareVersions]).
List<String> sortVersionsDesc(Iterable<String> versions) => versions.toList()
  ..sort((a, b) {
    final c = compareVersions(b, a);
    return c != 0 ? c : b.compareTo(a);
  });
