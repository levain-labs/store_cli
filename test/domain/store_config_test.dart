import 'package:store_cli/domain/store_config.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Map<Object?, Object?> _yaml(String text) =>
    loadYaml(text) as Map<Object?, Object?>;

const _valid = '''
play:
  package_name: jp.example.app
  language: ja-JP
  service_account: publisher@example.iam.gserviceaccount.com
asc:
  bundle_id: jp.example.ios
  locale: ja
''';

void main() {
  test('5つの値を読む(前後の空白は落とす)', () {
    final config = parseStoreConfig(
      _yaml(_valid.replaceFirst('ja\n', ' ja \n')),
    );
    expect(config.play.packageName, 'jp.example.app');
    expect(config.play.language, 'ja-JP');
    expect(
      config.play.serviceAccount,
      'publisher@example.iam.gserviceaccount.com',
    );
    expect(config.asc.bundleId, 'jp.example.ios');
    expect(config.asc.locale, 'ja');
  });

  test('節が無い・値が無い・空はどのキーかを示して失敗する', () {
    expect(
      () => parseStoreConfig(_yaml('play:\n  package_name: a\n')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('`asc:`'),
        ),
      ),
    );
    expect(
      () => parseStoreConfig(
        _yaml(_valid.replaceFirst('  language: ja-JP\n', '')),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('play.language'),
        ),
      ),
    );
    expect(
      () => parseStoreConfig(
        _yaml(_valid.replaceFirst('locale: ja', 'locale: ""')),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('asc.locale'),
        ),
      ),
    );
  });

  test('知らないキーは書き間違いとして失敗する(黙って無視しない)', () {
    expect(
      () => parseStoreConfig(_yaml('$_valid  packageName: x\n')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('asc.packageName'),
        ),
      ),
    );
    expect(
      () => parseStoreConfig(_yaml('${_valid}ios:\n  bundle_id: x\n')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('`ios`'),
        ),
      ),
    );
  });
}
