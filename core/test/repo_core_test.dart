import 'dart:convert';
import 'dart:typed_data';

import 'package:repo_core/repo_core.dart';
import 'package:repo_core/src/cert_check.dart';
import 'package:repo_core/src/lich_ca.dart';
import 'package:test/test.dart';

void main() {
  group('Lich repo protocol', () {
    test('encodes and decodes tab-separated headers', () {
      expect(
        LichRepoSource.encodeRequest({'action': 'list', 'client': '2.74'}),
        'action\tlist\tclient\t2.74',
      );
      expect(
        LichRepoSource.decodeHeader('Size\t123\tserver time\t99\n'),
        {'size': '123', 'server time': '99'},
      );
    });

    test('parses list and merges comments', () {
      const list = 'file\tgame\tsize\tlast update\tauthor\tdownloads\t'
          'rating total\trating count\ttags\n'
          'bigshot.lic\tgs\t619028\t1000\telanthia-online\t8816\t39\t4\t'
          'hunting, bigshot\n'
          'foo.lic\tdr\t10\t2000\tBob\t3\t0\t0\t\n';
      const comments = 'file\tgame\tcomments\n'
          'foo.lic\tdr\tline one\x12line\x14two\n'
          'bigshot.lic\tgs\t   \n';
      final entries =
          LichRepoSource.parseList(list, comments: comments, serverTime: null);

      expect(entries, hasLength(2));
      final big = entries[0];
      expect(big.name, 'bigshot.lic');
      expect(big.game, 'gs');
      expect(big.size, 619028);
      expect(big.downloads, 8816);
      expect(big.rating, closeTo(9.75, 0.001));
      expect(big.tags, ['hunting', 'bigshot']);
      expect(big.comments, isNull, reason: 'blank comments are dropped');
      expect(big.lastUpdated, DateTime.fromMillisecondsSinceEpoch(1000 * 1000));

      final foo = entries[1];
      expect(foo.rating, isNull);
      expect(foo.tags, isEmpty);
      expect(foo.comments, 'line one\nline\ttwo');
    });
  });

  group('Jinx manifest', () {
    test('parses entries and converts base64 SHA-1 to hex', () {
      final json = jsonEncode({
        'available': [
          {
            'file': '/assets/my%20script.lic',
            'type': 'script',
            'md5': base64.encode(List.generate(20, (i) => i)),
            'last_commit': 1770766412,
            'header': '/headers/my script.header',
            'tags': ['a', 'b'],
            'version': '3.6',
            'author': 'Luxelle',
          },
          {'file': '/assets/map.png', 'type': 'map'},
        ],
      });
      final e = JinxSource.parseManifest('jinx:test', json);
      expect(e, hasLength(2));
      expect(e[0].name, 'my script.lic');
      expect(e[0].path, '/assets/my%20script.lic');
      expect(e[0].version, '3.6');
      expect(e[0].sha1Hex, '000102030405060708090a0b0c0d0e0f10111213');
      expect(e[1].type, 'map');
      expect(e[1].sha1Hex, isNull);
    });

    test('entries round-trip through JSON', () {
      final e = CatalogEntry(
        sourceId: 'lich',
        name: 'a.lic',
        game: 'gs',
        tags: ['x'],
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(5000),
        downloads: 3,
      );
      final back = CatalogEntry.fromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>);
      expect(back.toJson(), e.toJson());
    });

    test('rejects a manifest without "available"', () {
      expect(() => JinxSource.parseManifest('x', '{}'),
          throwsA(isA<RepoException>()));
    });
  });

  group('script headers', () {
    test('extracts =begin block', () {
      expect(
        extractScriptHeader('\n=begin\n  hello\n  version: 1\n=end\ncode'),
        '  hello\n  version: 1',
      );
    });

    test('extracts leading # comments', () {
      expect(extractScriptHeader('# one\n## two\nputs 1'), 'one\ntwo');
    });

    test('returns empty when there is no header', () {
      expect(extractScriptHeader('puts 1'), '');
    });

    test('parses version from header', () {
      expect(parseScriptVersion('  author: x\n       version: 5.16.5\n'),
          '5.16.5');
      expect(parseScriptVersion('# Version: v2.1-beta'), '2.1-beta');
      expect(parseScriptVersion('no version here'), isNull);
    });

    test('compares versions', () {
      expect(compareVersions('4.12.9', '4.12.11'), lessThan(0));
      expect(compareVersions('2.0', '2'), 0);
      expect(compareVersions('10', '9'), greaterThan(0));
    });

    test('sorts versions numerically, newest first', () {
      expect(sortVersionsDesc(['4.12.9', '4.12.11', '3.93', '5.1.0']),
          ['5.1.0', '4.12.11', '4.12.9', '3.93']);
    });
  });

  group('pinned CA verifier', () {
    final verifier = PinnedCaVerifier(lichRepoCaPem);
    final caDer = base64.decode(lichRepoCaPem
        .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
        .replaceAll(RegExp(r'\s'), ''));

    test('accepts the self-signed root', () {
      expect(verifier.isSignedByCa(caDer), isTrue);
    });

    test('rejects a certificate with a tampered body', () {
      final bad = Uint8List.fromList(caDer);
      bad[200] ^= 0x01; // inside tbsCertificate
      expect(verifier.isSignedByCa(bad), isFalse);
    });

    test('rejects garbage', () {
      expect(verifier.isSignedByCa(Uint8List.fromList([1, 2, 3])), isFalse);
    });
  });
}
