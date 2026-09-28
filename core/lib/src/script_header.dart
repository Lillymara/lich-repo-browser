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

/// Orders version strings newest first, comparing numeric parts numerically
/// (so 4.12.11 sorts above 4.12.9).
List<String> sortVersionsDesc(Iterable<String> versions) {
  List<int> parts(String v) => [
        for (final p in v.split(RegExp(r'[^0-9]+')))
          if (p.isNotEmpty) int.parse(p)
      ];
  int cmp(String a, String b) {
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return y.compareTo(x);
    }
    return b.compareTo(a);
  }

  return versions.toList()..sort(cmp);
}
