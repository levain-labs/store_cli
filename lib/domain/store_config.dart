/// `store/store.yaml`(アプリ固有の値)の解釈。純関数(ファイルは読まない)。
///
/// CLIのコードにはアプリ固有の値(パッケージ名・バンドルID・サービスアカウント・
/// 言語)を書かず、すべてここを通して受け取る。アプリごとに用意するのは
/// `store/store.yaml` だけでよい。
library;

final class StoreConfig {
  const StoreConfig({required this.play, required this.asc});

  final PlayConfig play;
  final AscConfig asc;
}

final class PlayConfig {
  const PlayConfig({
    required this.packageName,
    required this.language,
    required this.serviceAccount,
  });

  /// Google Play のパッケージ名(applicationId)。
  final String packageName;

  /// 掲載情報の言語コード(`store/play/<language>/`)。
  final String language;

  /// Play Developer API でなりすますサービスアカウント。
  final String serviceAccount;
}

final class AscConfig {
  const AscConfig({required this.bundleId, required this.locale});

  /// App Store Connect のバンドルID。
  final String bundleId;

  /// 掲載情報のロケール(`store/asc/<locale>/`)。
  final String locale;
}

/// YAMLを読んだ [Map] から [StoreConfig] を組み立てる。
///
/// 足りない・空・文字列でない値は [FormatException](どのキーかを含む)。
/// 知らないキーは無視しない——書き間違い(`packageName` など)が黙って
/// 既定値に落ちるのを防ぐため、こちらも [FormatException] にする。
StoreConfig parseStoreConfig(Map<Object?, Object?> root) {
  final play = _section(root, 'play', const {
    'package_name',
    'language',
    'service_account',
  });
  final asc = _section(root, 'asc', const {'bundle_id', 'locale'});
  _rejectUnknownKeys(root, const {'play', 'asc'}, path: '');
  return StoreConfig(
    play: PlayConfig(
      packageName: _string(play, 'package_name', section: 'play'),
      language: _string(play, 'language', section: 'play'),
      serviceAccount: _string(play, 'service_account', section: 'play'),
    ),
    asc: AscConfig(
      bundleId: _string(asc, 'bundle_id', section: 'asc'),
      locale: _string(asc, 'locale', section: 'asc'),
    ),
  );
}

Map<Object?, Object?> _section(
  Map<Object?, Object?> root,
  String name,
  Set<String> knownKeys,
) {
  final value = root[name];
  if (value is! Map<Object?, Object?>) {
    throw FormatException('store.yaml: `$name:` の節がありません');
  }
  _rejectUnknownKeys(value, knownKeys, path: '$name.');
  return value;
}

String _string(
  Map<Object?, Object?> values,
  String key, {
  required String section,
}) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('store.yaml: `$section.$key` を文字列で指定してください');
  }
  return value.trim();
}

void _rejectUnknownKeys(
  Map<Object?, Object?> map,
  Set<String> known, {
  required String path,
}) {
  for (final key in map.keys) {
    if (!known.contains(key)) {
      throw FormatException(
        'store.yaml: 知らないキー `$path$key`(使えるのは ${known.join(', ')})',
      );
    }
  }
}
