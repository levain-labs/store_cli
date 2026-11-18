/// リリースノート(両ストア共通の「このバージョンの変更点」)。
///
/// 正本は `store/release-notes/<バージョン名>.txt` の1ファイルで、
/// Playの `releaseNotes` とASCの `whatsNew` の両方へ同じ文章を流し込む。
library;

final _versionName = RegExp(r'^\d+\.\d+\.\d+$');

/// バージョン名(Flutterなら `pubspec.yaml` の `version:` の `+` より前。例 `1.0.1`)
/// からリリースノートのファイル名を返す。形式が違えば [FormatException]。
String releaseNotesFileName(String versionName) {
  if (!_versionName.hasMatch(versionName)) {
    throw FormatException('バージョン名は「1.0.1」の形式で指定してください', versionName);
  }
  return '$versionName.txt';
}
