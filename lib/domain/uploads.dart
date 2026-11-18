/// ビルドのアップロード(`play upload` / `asc upload`)の判断。
library;

/// これからアップロードする番号 [requested] が、ストアにある番号 [existing]
/// のどれよりも大きいかを確かめる。問題があればその説明、無ければ null。
///
/// ストアは同じ番号の再アップロードを拒否する。Playは一度でもアップロードした
/// versionCode(トラックから外したものも含む)を二度と受け付けないため、
/// 「最大より大きい」で判定する。
String? checkNewBuildNumber(Iterable<int> existing, int requested) {
  if (requested < 1) return 'build number は1以上です: $requested';
  if (existing.isEmpty) return null;
  final max = existing.reduce((a, b) => a > b ? a : b);
  if (requested > max) return null;
  return 'build number $requested はストアにある最大の番号 $max 以下です。$max より大きい番号で作り直してください';
}

/// `xcrun altool --upload-package` に渡す引数。
///
/// `--apple-id` はApp Store Connectのアプリの数字のID(APIの `apps` の id)。
/// 鍵はファイルで渡す(`--auth-string` は引数に秘密が載り、ps から見えるため使わない)。
List<String> altoolUploadArgs({
  required String ipaPath,
  required String appleId,
  required String bundleId,
  required String versionName,
  required String buildNumber,
  required String keyId,
  required String issuerId,
  required String p8Path,
}) => [
  'altool',
  '--upload-package',
  ipaPath,
  '--platform',
  'ios',
  '--apple-id',
  appleId,
  '--bundle-id',
  bundleId,
  '--bundle-version',
  buildNumber,
  '--bundle-short-version-string',
  versionName,
  '--api-key',
  keyId,
  '--api-issuer',
  issuerId,
  '--p8-file-path',
  p8Path,
];
