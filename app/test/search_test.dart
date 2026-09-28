import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/search_query.dart';
import 'package:repo_core/repo_core.dart';

ScriptGroup group(
  String name, {
  String? author,
  List<String> tags = const [],
  String? comments,
  String source = 'lich',
  String game = 'gs',
  int? downloads,
  int ratingTotal = 0,
  int ratingCount = 0,
  int? size,
  DateTime? updated,
  String? version,
}) => ScriptGroup(name, [
  CatalogEntry(
    sourceId: source,
    name: name,
    game: game,
    author: author,
    tags: tags,
    comments: comments,
    downloads: downloads,
    ratingTotal: ratingTotal,
    ratingCount: ratingCount,
    size: size,
    lastUpdated: updated,
    version: version,
  ),
]);

final now = DateTime.now();
final scripts = [
  group(
    'bigshot.lic',
    author: 'elanthia-online',
    tags: ['hunting', 'combat'],
    downloads: 8816,
    ratingTotal: 39,
    ratingCount: 4,
    size: 619028,
    updated: now.subtract(const Duration(days: 4)),
  ),
  group(
    'mybounty.lic',
    author: 'Luxelle',
    tags: ['bounty', 'boost bounty'],
    source: 'jinx:elanthia-online',
    version: '3.6',
    updated: DateTime(2026, 2, 10),
  ),
  group(
    'sbounty-bigshot.lic',
    author: 'elanthia-online',
    tags: ['bounty'],
    downloads: 110,
    size: 12000,
    updated: DateTime(2022, 11, 4),
  ),
  group(
    'drhunt.lic',
    author: 'Someone',
    game: 'dr',
    comments: 'not for gemstone',
    source: 'jinx:mirror',
    updated: DateTime(2020, 12, 19),
  ),
  group(
    'ui-layout.xml',
    author: 'Tysong',
    downloads: 5,
    comments: 'not for gemstone',
  ),
];

List<String> search(String q) => [
  for (final g in scripts)
    if (SearchQuery.parse(q).matches(g)) g.name,
];

void main() {
  test('empty query matches everything', () {
    expect(search(''), hasLength(scripts.length));
    expect(SearchQuery.parse('  ').isEmpty, isTrue);
  });

  test('implicit and explicit AND', () {
    expect(search('bigshot bounty'), ['sbounty-bigshot.lic']);
    expect(search('bigshot AND bounty'), ['sbounty-bigshot.lic']);
    expect(search('bigshot & bounty'), ['sbounty-bigshot.lic']);
  });

  test('OR and precedence (AND binds tighter)', () {
    expect(search('drhunt OR mybounty'), ['mybounty.lic', 'drhunt.lic']);
    expect(search('drhunt | tysong'), ['drhunt.lic', 'ui-layout.xml']);
    // bounty AND (bigshot) OR drhunt  ==  (bounty bigshot) OR drhunt
    expect(search('bounty bigshot OR drhunt'), [
      'sbounty-bigshot.lic',
      'drhunt.lic',
    ]);
  });

  test('NOT, -, !', () {
    expect(search('bounty NOT bigshot'), ['mybounty.lic']);
    expect(search('bounty -bigshot'), ['mybounty.lic']);
    expect(search('bounty !bigshot'), ['mybounty.lic']);
    expect(search('NOT NOT drhunt'), ['drhunt.lic']);
  });

  test('parentheses', () {
    expect(search('(mybounty OR drhunt) -luxelle'), ['drhunt.lic']);
    expect(search('-(bounty OR hunting)'), ['drhunt.lic', 'ui-layout.xml']);
  });

  test('lower-case and/or/not are plain words', () {
    expect(search('not for'), ['ui-layout.xml']); // matches the comment
  });

  test('hyphenated words are not negated', () {
    expect(search('sbounty-bigshot'), ['sbounty-bigshot.lic']);
    expect(search('elanthia-online bounty'), ['sbounty-bigshot.lic']);
  });

  test('phrases', () {
    expect(search('"boost bounty"'), ['mybounty.lic']);
    expect(search('tag:"boost bounty"'), ['mybounty.lic']);
  });

  test('text fields and aliases', () {
    expect(search('author:tysong'), ['ui-layout.xml']);
    expect(search('by:luxelle'), ['mybounty.lic']);
    expect(search('tag:combat'), ['bigshot.lic']);
    expect(search('comment:gemstone'), ['ui-layout.xml']);
    expect(search('source:mirror'), ['drhunt.lic']);
    expect(search('game:dr'), ['drhunt.lic']);
    expect(search('version:3.6'), ['mybounty.lic']);
    // Fields are exact about where they look.
    expect(search('name:elanthia'), isEmpty);
  });

  test('wildcards match the whole field', () {
    expect(search('name:big*'), ['bigshot.lic']);
    expect(search('name:*.xml'), ['ui-layout.xml']);
    expect(search('name:?rhunt.lic'), ['drhunt.lic']);
    expect(search('name:*bounty*'), ['mybounty.lic', 'sbounty-bigshot.lic']);
  });

  test('numeric comparisons', () {
    expect(search('downloads:>100'), ['bigshot.lic', 'sbounty-bigshot.lic']);
    expect(search('downloads:<=5'), ['ui-layout.xml']);
    expect(search('rating:>=9'), ['bigshot.lic']);
    expect(search('votes:4'), ['bigshot.lic']);
    expect(search('size:>500k'), ['bigshot.lic']);
    expect(search('size:<10kb'), isEmpty);
    expect(search('size:<12kb'), ['sbounty-bigshot.lic']); // 12kb = 12288
    expect(search('size:<=12000'), ['sbounty-bigshot.lic']);
  });

  test('dates and ages', () {
    expect(search('updated:>=2026-01-01'), ['bigshot.lic', 'mybounty.lic']);
    expect(search('updated:<2021'), ['drhunt.lic']);
    expect(search('updated:=2022-11-04'), ['sbounty-bigshot.lic']);
    expect(search('age:<30d'), ['bigshot.lic']);
    expect(search('age:>3y'), ['sbounty-bigshot.lic', 'drhunt.lic']);
  });

  test('combined', () {
    expect(
      search('(tag:bounty OR tag:hunting) downloads:>200 -source:mirror'),
      ['bigshot.lic'],
    );
  });

  test('unknown field is plain text', () {
    final q = SearchQuery.parse('http://x');
    expect(q.warning, isNull);
    expect(q.matches(scripts.first), isFalse);
  });

  test('lenient parsing reports what it ignored', () {
    expect(SearchQuery.parse('(bounty OR bigshot').warning, contains(')'));
    expect(search('(bounty OR bigshot'), [
      'bigshot.lic',
      'mybounty.lic',
      'sbounty-bigshot.lic',
    ]);
    expect(SearchQuery.parse('bounty)').warning, contains(')'));
    expect(search('bounty) bigshot'), ['sbounty-bigshot.lic']);
    expect(SearchQuery.parse('bounty OR').warning, contains('OR'));
    expect(search('bounty OR'), ['mybounty.lic', 'sbounty-bigshot.lic']);
    expect(SearchQuery.parse('bounty NOT').warning, contains('NOT'));
    expect(SearchQuery.parse('(NOT)').warning, isNotNull);
    expect(SearchQuery.parse('downloads:lots').warning, contains('downloads'));
    expect(SearchQuery.parse('author:').warning, contains('author'));
    expect(SearchQuery.parse('bounty').warning, isNull);
  });
}
