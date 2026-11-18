import 'dart:io';

import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:store_cli/domain/store_config.dart';
import 'package:store_cli/store_files.dart';
import 'package:test/test.dart';

const testConfig = StoreConfig(
  play: PlayConfig(
    packageName: 'jp.example.app',
    language: 'ja-JP',
    serviceAccount: 'publisher@example.iam.gserviceaccount.com',
  ),
  asc: AscConfig(bundleId: 'jp.example.app', locale: 'ja'),
);

void main() {
  late Directory root;
  late StoreFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('store_files_test');
    files = StoreFiles(root, config: testConfig);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('pull で書いたものを読み直すと同じ値(ストアに無い項目はファイルを作らない)', () {
    files.writePlayText({
      PlayTextField.title: 'サンプルアプリ',
      PlayTextField.shortDescription: null,
    });
    expect(files.readPlayText(), {PlayTextField.title: 'サンプルアプリ'});
    expect(
      File('${root.path}/play/ja-JP/title.txt').readAsStringSync(),
      'サンプルアプリ\n',
      reason: 'エディタで開いても差分にならないよう末尾に改行を1つ付ける',
    );
  });

  test('ASCのテキストは asc/ja/ 配下', () {
    files.writeAscText({AscTextField.keywords: '食品表示,ラベル'});
    expect(File('${root.path}/asc/ja/keywords.txt').existsSync(), isTrue);
    expect(files.readAscText(), {AscTextField.keywords: '食品表示,ラベル'});
  });

  test('画像のファイル・ディレクトリが無い種類は null(管理しない)', () {
    expect(files.readPlayImages(PlayImageType.icon), isNull);
    expect(files.readPlayImages(PlayImageType.phoneScreenshots), isNull);
  });

  test('スクリーンショットはファイル名順、PNG以外は無視', () {
    final dir = Directory('${root.path}/play/ja-JP/images/phoneScreenshots')
      ..createSync(recursive: true);
    for (final name in ['02.png', '01.png', 'memo.txt']) {
      File('${dir.path}/$name').writeAsBytesSync([1]);
    }
    expect(
      files
          .readPlayImages(PlayImageType.phoneScreenshots)!
          .map((i) => i.fileName),
      ['01.png', '02.png'],
    );
  });

  test('ASCのスクリーンショットはディレクトリ名を画面サイズ種別として読む', () {
    final dir = Directory('${root.path}/asc/ja/screenshots/APP_IPHONE_67')
      ..createSync(recursive: true);
    File('${dir.path}/01.png').writeAsBytesSync([1]);
    expect(files.readAscScreenshots().keys, ['APP_IPHONE_67']);
  });

  group('readReleaseNotes', () {
    test('release-notes/<バージョン名>.txt を読む', () {
      File('${root.path}/release-notes/1.0.1.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('不具合を直しました\n');
      expect(files.readReleaseNotes('1.0.1'), '不具合を直しました');
    });

    test('無い・空・バージョン名の形式違いは利用者向けのエラー', () {
      expect(
        () => files.readReleaseNotes('1.0.1'),
        throwsA(isA<CliException>()),
      );
      File('${root.path}/release-notes/1.0.2.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('\n');
      expect(
        () => files.readReleaseNotes('1.0.2'),
        throwsA(isA<CliException>()),
      );
      expect(() => files.readReleaseNotes('1.0'), throwsA(isA<CliException>()));
    });
  });

  group('store.yaml', () {
    test('open は store.yaml を読んで config にする', () {
      File('${root.path}/store.yaml').writeAsStringSync('''
play:
  package_name: jp.example.app
  language: en-US
  service_account: publisher@example.iam.gserviceaccount.com
asc:
  bundle_id: jp.example.ios
  locale: en-US
''');
      final opened = StoreFiles.open(root);
      expect(opened.config.play.packageName, 'jp.example.app');
      expect(opened.playLanguage, 'en-US');
      expect(opened.ascLocale, 'en-US');
      opened.writePlayText({PlayTextField.title: 'Example'});
      expect(
        File('${root.path}/play/en-US/title.txt').existsSync(),
        isTrue,
        reason: 'テキストの置き場は store.yaml の言語で決まる',
      );
    });

    test('store.yaml が無い・壊れている・知らないキーは CliException', () {
      expect(() => StoreFiles.open(root), throwsA(isA<CliException>()));
      File('${root.path}/store.yaml').writeAsStringSync('play: [\n');
      expect(() => StoreFiles.open(root), throwsA(isA<CliException>()));
      File('${root.path}/store.yaml').writeAsStringSync('''
play:
  packageName: jp.example.app
asc:
  bundle_id: x
  locale: ja
''');
      expect(
        () => StoreFiles.open(root),
        throwsA(
          isA<CliException>().having(
            (e) => e.message,
            'message',
            contains('play.packageName'),
          ),
        ),
      );
    });
  });
}
