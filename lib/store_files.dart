/// 境界: `store/`(掲載情報の正本)の読み書き。
///
/// ```
/// store/
/// ├─ store.yaml                       # アプリ固有の値(domain/store_config.dart)
/// ├─ play/<language>/{title,short_description,full_description}.txt
/// ├─ play/<language>/images/{icon.png,featureGraphic.png,phoneScreenshots/*.png}
/// ├─ asc/<locale>/{name,subtitle,description,…}.txt
/// ├─ asc/<locale>/screenshots/<画面サイズ種別>/*.png
/// └─ release-notes/<バージョン名>.txt
/// ```
///
/// `<language>` / `<locale>` は `store.yaml` の値(例: ja-JP / ja)。
///
/// ファイルやディレクトリが無い項目は「このリポジトリでは管理しない」として扱い、
/// 読み取り結果に含めない(ストアの値を誤って空にしないため)。
library;

import 'dart:io';

import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:store_cli/domain/release_notes.dart';
import 'package:store_cli/domain/store_config.dart';
import 'package:yaml/yaml.dart';

/// アプリ固有の値を置くファイル。`store/` を見つける目印でもある。
const storeConfigFileName = 'store.yaml';

final class StoreFiles {
  StoreFiles(this.root, {required this.config});

  /// `--store-dir` の指定があればそれを、無ければカレントディレクトリから
  /// 上へたどって `store/store.yaml` のあるディレクトリの `store/` を使う。
  /// どちらも `store.yaml` を読んで [config] にする。
  factory StoreFiles.locate({String? storeDir}) {
    if (storeDir != null) return StoreFiles.open(Directory(storeDir));
    var dir = Directory.current.absolute;
    while (true) {
      final store = Directory('${dir.path}/store');
      if (File('${store.path}/$storeConfigFileName').existsSync()) {
        return StoreFiles.open(store);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw CliException(
          'store/$storeConfigFileName が見つかりません(カレントディレクトリから上へ探しました)。'
          '--store-dir で store/ の場所を指定してください',
        );
      }
      dir = parent;
    }
  }

  /// `store.yaml` を読んで開く。無い・壊れているときは [CliException]。
  factory StoreFiles.open(Directory root) {
    final file = File('${root.path}/$storeConfigFileName');
    if (!file.existsSync()) {
      throw CliException(
        '${file.path} がありません。'
        'アプリ固有の値(パッケージ名・バンドルID・サービスアカウント・言語)をここに書いてください',
      );
    }
    final Object? parsed;
    try {
      parsed = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      throw CliException('${file.path} を読めません: ${e.message}');
    }
    if (parsed is! Map<Object?, Object?>) {
      throw CliException('${file.path}: 先頭が `play:` / `asc:` の節になっていません');
    }
    try {
      return StoreFiles(root, config: parseStoreConfig(parsed));
    } on FormatException catch (e) {
      throw CliException('${file.path}: ${e.message}');
    }
  }

  final Directory root;

  /// `store.yaml` の値。
  final StoreConfig config;

  /// Google Play の言語コード(`store.yaml` の `play.language`)。
  String get playLanguage => config.play.language;

  /// App Store Connect のロケール(`store.yaml` の `asc.locale`)。
  String get ascLocale => config.asc.locale;

  Directory get _playDir => Directory('${root.path}/play/$playLanguage');
  Directory get _ascDir => Directory('${root.path}/asc/$ascLocale');

  // ---- テキスト ----

  Map<PlayTextField, String> readPlayText() =>
      _readText(_playDir, PlayTextField.values);

  Map<AscTextField, String> readAscText() =>
      _readText(_ascDir, AscTextField.values);

  /// `pull` の書き出し。ストアに値が無い項目(null)はファイルを作らない。
  /// 書いたファイルのパスを返す。
  List<String> writePlayText(Map<PlayTextField, String?> values) =>
      _writeText(_playDir, values);

  List<String> writeAscText(Map<AscTextField, String?> values) =>
      _writeText(_ascDir, values);

  Map<F, String> _readText<F extends TextFieldSpec>(
    Directory dir,
    List<F> fields,
  ) => {
    for (final field in fields)
      if (File('${dir.path}/${field.fileName}') case final file
          when file.existsSync())
        field: normalizeText(file.readAsStringSync()),
  };

  List<String> _writeText<F extends TextFieldSpec>(
    Directory dir,
    Map<F, String?> values,
  ) {
    dir.createSync(recursive: true);
    return [
      for (final MapEntry(key: field, value: value) in values.entries)
        if (value != null)
          (File(
            '${dir.path}/${field.fileName}',
          )..writeAsStringSync('${normalizeText(value)}\n')).path,
    ];
  }

  // ---- 画像 ----

  /// Playの画像。ファイル(1枚の種類)またはディレクトリ(複数枚の種類)が
  /// 無ければ null(管理しない)。
  List<LocalImage>? readPlayImages(PlayImageType type) {
    final base = '${_playDir.path}/images/${type.apiName}';
    if (type.isSingle) {
      final file = File('$base.png');
      return file.existsSync()
          ? [
              LocalImage(
                fileName: '${type.apiName}.png',
                bytes: file.readAsBytesSync(),
              ),
            ]
          : null;
    }
    final dir = Directory(base);
    return dir.existsSync() ? _readPngs(dir) : null;
  }

  /// ASCのスクリーンショット。`screenshots/` 直下のディレクトリ名を
  /// 画面サイズ種別(例 `APP_IPHONE_67`)として読む。ディレクトリが無い種別は管理しない。
  Map<String, List<LocalImage>> readAscScreenshots() {
    final dir = Directory('${_ascDir.path}/screenshots');
    if (!dir.existsSync()) return {};
    final sets = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return {
      for (final set in sets)
        set.uri.pathSegments.lastWhere((s) => s.isNotEmpty): _readPngs(set),
    };
  }

  List<LocalImage> _readPngs(Directory dir) {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.png'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final file in files)
        LocalImage(
          fileName: file.uri.pathSegments.last,
          bytes: file.readAsBytesSync(),
        ),
    ];
  }

  // ---- リリースノート ----

  /// `store/release-notes/<バージョン名>.txt`。無ければ [CliException]。
  String readReleaseNotes(String versionName) {
    final String fileName;
    try {
      fileName = releaseNotesFileName(versionName);
    } on FormatException catch (e) {
      throw CliException('${e.message}: $versionName');
    }
    final file = File('${root.path}/release-notes/$fileName');
    if (!file.existsSync()) {
      throw CliException('リリースノートがありません: ${file.path}');
    }
    final text = normalizeText(file.readAsStringSync());
    if (text.isEmpty) {
      throw CliException('リリースノートが空です: ${file.path}');
    }
    return text;
  }
}
