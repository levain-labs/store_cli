/// 境界: Play Developer API の認証(鍵ファイルを使わない)。
///
/// 利用者本人の gcloud ログインから、サービスアカウント(`store.yaml` の
/// `play.service_account`。Play Console に招待し「リリースの管理」「ストアでの
/// 表示の管理」を付けたもの)になりすましたアクセストークンを得る。JSONキーを1つも発行しない。
///
/// CI化するときは、ここをWorkload Identity連携で得たトークンに差し替えるだけでよい。
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:store_cli/cli_exception.dart';

/// Play Developer API が受け付けるスコープはこれだけ(cloud-platform では通らない)。
const _androidPublisherScope =
    'https://www.googleapis.com/auth/androidpublisher';

/// `gcloud auth print-access-token` でなりすましトークン(1時間有効)を得る。
///
/// `--scopes` はヘルプに出ない隠しフラグだが、なりすましと組み合わせて効く。
/// 標準エラーには紛らわしい警告(「scopes are ignored」等)が出ることがあるので、
/// 標準出力だけをトークンとして読み、標準エラーは失敗したときだけ見せる。
Future<String> fetchPlayAccessToken({required String serviceAccount}) async {
  final ProcessResult result;
  try {
    result = await Process.run('gcloud', [
      'auth',
      'print-access-token',
      '--impersonate-service-account=$serviceAccount',
      '--scopes=$_androidPublisherScope',
    ]);
  } on ProcessException catch (e) {
    throw CliException('gcloud を実行できません(インストールされていますか?): ${e.message}');
  }
  final token = (result.stdout as String).trim();
  if (result.exitCode != 0 || token.isEmpty) {
    throw CliException(
      'アクセストークンを取得できませんでした(gcloud の終了コード ${result.exitCode})。\n'
      '- `gcloud auth login` 済みか\n'
      '- 自分のアカウントに $serviceAccount への '
      'roles/iam.serviceAccountTokenCreator が付いているか\n'
      'を確認してください。\n'
      '${(result.stderr as String).trim()}',
    );
  }
  return token;
}

/// すべてのリクエストに `Authorization: Bearer` を付ける http.Client。
final class BearerClient extends http.BaseClient {
  BearerClient(this._token, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final String _token;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
