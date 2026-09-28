import 'catalog_model.dart';
import 'ui/format.dart';

/// Boolean search over [ScriptGroup]s.
///
///   bigshot hunting          both words (AND is implied)
///   bounty OR bigshot        either word          (also `|`)
///   NOT mirror / -mirror     exclude              (also `!`)
///   (a OR b) c               grouping
///   "boost bounty"           exact phrase
///   author:tysong            field search; see [fields]
///   name:big*  name:*.xml    `*` / `?` wildcards match the whole field
///   downloads:>100  rating:>=8  size:<50k  age:<30d  updated:>2025-06-01
///
/// Operators are upper-case so the words "and"/"or"/"not" still search.
/// Parsing never fails: unbalanced parentheses and stray operators are
/// ignored and reported in [warning].
class SearchQuery {
  SearchQuery._(this.source, this._root, this.warning);

  factory SearchQuery.parse(String input) {
    final p = _Parser(_tokenize(input));
    final root = p.parseAll();
    return SearchQuery._(input, root, p.warning);
  }

  static const fields = {
    'name': 'file name',
    'author': 'author',
    'tag': 'tags',
    'comment': 'Lich repo comments',
    'source': 'lich, elanthia-online, mirror, …',
    'game': 'gs, dr, any',
    'type': 'script, data, map, engine',
    'version': 'published version',
    'downloads': 'number, e.g. >100',
    'rating': 'number, e.g. >=8',
    'votes': 'number of ratings',
    'size': 'bytes; k/m suffixes, e.g. <50k',
    'updated': 'date, e.g. >2025-06-01',
    'age': 'time since update, e.g. <30d, >2y (d/w/m/y)',
  };

  static const _aliases = {
    'tags': 'tag',
    'comments': 'comment',
    'file': 'name',
    'by': 'author',
    'repo': 'source',
  };

  final String source;
  final _Node? _root;

  /// Set when part of the input was ignored (e.g. a missing `)`).
  final String? warning;

  bool get isEmpty => _root == null;

  bool matches(ScriptGroup g) => _root?.eval(g) ?? true;
}

// ---------------------------------------------------------------------------
// Tokens

enum _T { word, phrase, and, or, not, open, close }

class _Tok {
  _Tok(this.type, [this.text = '', this.field]);
  final _T type;
  final String text;
  final String? field;
}

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c.trim().isEmpty) {
      i++;
    } else if (c == '(') {
      out.add(_Tok(_T.open));
      i++;
    } else if (c == ')') {
      out.add(_Tok(_T.close));
      i++;
    } else if (c == '|') {
      out.add(_Tok(_T.or));
      i += s.startsWith('||', i) ? 2 : 1;
    } else if (c == '&') {
      out.add(_Tok(_T.and));
      i += s.startsWith('&&', i) ? 2 : 1;
    } else if ((c == '-' || c == '!') &&
        i + 1 < s.length &&
        s[i + 1].trim().isNotEmpty) {
      // Only a prefix: "auto-hunt" stays one word.
      out.add(_Tok(_T.not));
      i++;
    } else {
      // A word, a "phrase", or field:value / field:"phrase".
      String? field;
      final m = RegExp(r'([A-Za-z]+):').matchAsPrefix(s, i);
      if (m != null) {
        final name = m[1]!.toLowerCase();
        final canonical = SearchQuery._aliases[name] ?? name;
        if (SearchQuery.fields.containsKey(canonical)) {
          field = canonical;
          i = m.end;
        }
      }
      if (i < s.length && s[i] == '"') {
        final end = s.indexOf('"', i + 1);
        final text = s.substring(i + 1, end < 0 ? s.length : end);
        out.add(_Tok(_T.phrase, text, field));
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      final start = i;
      while (i < s.length &&
          s[i].trim().isNotEmpty &&
          !'()|&"'.contains(s[i])) {
        i++;
      }
      final word = s.substring(start, i);
      if (field == null && word == 'AND') {
        out.add(_Tok(_T.and));
      } else if (field == null && word == 'OR') {
        out.add(_Tok(_T.or));
      } else if (field == null && word == 'NOT') {
        out.add(_Tok(_T.not));
      } else if (word.isNotEmpty || field != null) {
        out.add(_Tok(_T.word, word, field));
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Parser (recursive descent; precedence NOT > AND > OR)

class _Parser {
  _Parser(this.toks);
  final List<_Tok> toks;
  var pos = 0;
  String? warning;

  _Tok? get peek => pos < toks.length ? toks[pos] : null;

  _Node? parseAll() {
    final n = _or();
    while (pos < toks.length) {
      // Only an unmatched ')' can stop the top level early.
      warning ??= 'Ignored an unmatched ")"';
      pos++;
      final rest = _or();
      if (rest != null) {
        return _And([?n, rest]);
      }
    }
    return n;
  }

  _Node? _or() {
    final parts = <_Node>[];
    final first = _and();
    if (first != null) parts.add(first);
    while (peek?.type == _T.or) {
      pos++;
      final next = _and();
      if (next != null) {
        parts.add(next);
      } else {
        warning ??= 'Ignored an OR with nothing after it';
      }
    }
    if (parts.isEmpty) return null;
    return parts.length == 1 ? parts.first : _Or(parts);
  }

  _Node? _and() {
    final parts = <_Node>[];
    while (true) {
      final t = peek;
      if (t == null || t.type == _T.or || t.type == _T.close) break;
      if (t.type == _T.and) {
        pos++;
        continue;
      }
      final n = _unary();
      if (n != null) parts.add(n);
    }
    if (parts.isEmpty) return null;
    return parts.length == 1 ? parts.first : _And(parts);
  }

  _Node? _unary() {
    final t = peek!;
    if (t.type == _T.not) {
      pos++;
      final next = peek?.type;
      final inner =
          next == null || next == _T.close || next == _T.or || next == _T.and
          ? null
          : _unary();
      if (inner == null) {
        warning ??= 'Ignored a NOT with nothing after it';
        return null;
      }
      return _Not(inner);
    }
    if (t.type == _T.open) {
      pos++;
      final inner = _or();
      if (peek?.type == _T.close) {
        pos++;
      } else {
        warning ??= 'Added a missing ")"';
      }
      return inner;
    }
    pos++;
    return _term(t);
  }

  _Node? _term(_Tok t) {
    final field = t.field;
    final value = t.text;
    if (value.isEmpty) {
      if (field != null) warning ??= 'Ignored "$field:" with no value';
      return null;
    }
    switch (field) {
      case 'downloads' || 'rating' || 'votes' || 'size':
        final cmp = _NumCmp.parse(value, units: field == 'size');
        if (cmp == null) {
          warning ??= "Couldn't read $field:$value";
          return null;
        }
        return _NumTerm(field!, cmp);
      case 'updated' || 'age':
        final cmp = field == 'age' ? _ageCmp(value) : _dateCmp(value);
        if (cmp == null) {
          warning ??= "Couldn't read $field:$value";
          return null;
        }
        return _DateTerm(cmp);
      default:
        return _TextTerm(
          field,
          value.toLowerCase(),
          glob: t.type == _T.word && RegExp(r'[*?]').hasMatch(value),
        );
    }
  }

  /// `updated:>2025-06-01` → compare against that date.
  _DateCmp? _dateCmp(String v) {
    final m = RegExp(r'^(>=|<=|>|<|=)?(\d{4})-?(\d{1,2})?-?(\d{1,2})?$')
        .firstMatch(v);
    if (m == null) return null;
    final date = DateTime(
      int.parse(m[2]!),
      int.parse(m[3] ?? '1'),
      int.parse(m[4] ?? '1'),
    );
    return _DateCmp(m[1] ?? '>=', date);
  }

  /// `age:<30d` means updated less than 30 days ago, i.e. after that date.
  _DateCmp? _ageCmp(String v) {
    final m = RegExp(
      r'^(>=|<=|>|<|=)?(\d+(?:\.\d+)?)([dwmy])?$',
      caseSensitive: false,
    ).firstMatch(v);
    if (m == null) return null;
    final n = double.parse(m[2]!);
    final days =
        n *
        switch ((m[3] ?? 'd').toLowerCase()) {
          'w' => 7,
          'm' => 30.44,
          'y' => 365.25,
          _ => 1,
        };
    final date = DateTime.now().subtract(
      Duration(minutes: (days * 24 * 60).round()),
    );
    // Younger than N days = updated after (now - N days): flip the operator.
    const flip = {'<': '>', '<=': '>=', '>': '<', '>=': '<=', '=': '='};
    return _DateCmp(flip[m[1] ?? '<']!, date);
  }
}

// ---------------------------------------------------------------------------
// Evaluation

abstract class _Node {
  bool eval(ScriptGroup g);
}

class _And extends _Node {
  _And(this.parts);
  final List<_Node> parts;
  @override
  bool eval(ScriptGroup g) => parts.every((p) => p.eval(g));
}

class _Or extends _Node {
  _Or(this.parts);
  final List<_Node> parts;
  @override
  bool eval(ScriptGroup g) => parts.any((p) => p.eval(g));
}

class _Not extends _Node {
  _Not(this.inner);
  final _Node inner;
  @override
  bool eval(ScriptGroup g) => !inner.eval(g);
}

class _TextTerm extends _Node {
  _TextTerm(this.field, this.value, {required bool glob})
    : _glob = glob
          ? RegExp(
              '^${RegExp.escape(value).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
              dotAll: true,
            )
          : null;

  final String? field;
  final String value;
  final RegExp? _glob;

  Iterable<String> _values(ScriptGroup g) => switch (field) {
    null => [g.searchText],
    'name' => [g.name],
    'author' => [for (final e in g.entries) ?e.author],
    'tag' => g.tags,
    'comment' => [?g.comments],
    'source' => {for (final e in g.entries) sourceLabel(e.sourceId)},
    'game' => g.games,
    'type' => [g.type],
    'version' => [for (final e in g.entries) ?e.version],
    _ => const [],
  };

  @override
  bool eval(ScriptGroup g) {
    for (final raw in _values(g)) {
      final v = raw.toLowerCase();
      if (_glob != null ? _glob.hasMatch(v) : v.contains(value)) return true;
    }
    return false;
  }
}

class _NumCmp {
  _NumCmp(this.op, this.n);
  final String op;
  final double n;

  static _NumCmp? parse(String v, {bool units = false}) {
    final m = RegExp(
      r'^(>=|<=|>|<|=)?(\d+(?:\.\d+)?)([kmg]b?|b)?$',
      caseSensitive: false,
    ).firstMatch(v);
    if (m == null || (!units && m[3] != null)) return null;
    final mult = switch (m[3]?.toLowerCase().substring(0, 1)) {
      'k' => 1024,
      'm' => 1024 * 1024,
      'g' => 1024 * 1024 * 1024,
      _ => 1,
    };
    return _NumCmp(m[1] ?? '=', double.parse(m[2]!) * mult);
  }

  bool test(num x) => switch (op) {
    '>' => x > n,
    '>=' => x >= n,
    '<' => x < n,
    '<=' => x <= n,
    _ => x == n,
  };
}

class _NumTerm extends _Node {
  _NumTerm(this.field, this.cmp);
  final String field;
  final _NumCmp cmp;

  @override
  bool eval(ScriptGroup g) {
    final num? x = switch (field) {
      'downloads' => g.downloads,
      'rating' => g.rating,
      'votes' => g.ratingCount,
      'size' => g.entries.map((e) => e.size).nonNulls.firstOrNull,
      _ => null,
    };
    return x != null && cmp.test(x);
  }
}

class _DateCmp {
  _DateCmp(this.op, this.date);
  final String op;
  final DateTime date;

  bool test(DateTime t) => switch (op) {
    '>' => t.isAfter(date),
    '>=' => !t.isBefore(date),
    '<' => t.isBefore(date),
    '<=' => !t.isAfter(date),
    // "=" matches the whole day.
    _ => t.year == date.year && t.month == date.month && t.day == date.day,
  };
}

class _DateTerm extends _Node {
  _DateTerm(this.cmp);
  final _DateCmp cmp;
  @override
  bool eval(ScriptGroup g) {
    final t = g.lastUpdated;
    return t != null && cmp.test(t);
  }
}
