/// 境界: App Store Connect API の認証(ES256のJWT)。
///
/// Appleには鍵以外の認証手段が無いため、.p8(App Store Connect APIキー)を使う。
/// 鍵は1Passwordにだけ置き、`op run --env-file=store/.env.store` が
/// このプロセスの環境変数へだけ展開する(ディスクに書かない)。
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:store_cli/cli_exception.dart';

/// App Store Connect APIキーの3点セット。
final class AscCredentials {
  const AscCredentials({
    required this.keyId,
    required this.issuerId,
    required this.privateKeyPem,
  });

  /// `store/.env.store` が `op run` で展開する環境変数から読む。
  factory AscCredentials.fromEnvironment(Map<String, String> env) {
    const names = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY'];
    final missing = [
      for (final name in names)
        if ((env[name] ?? '').trim().isEmpty) name,
    ];
    if (missing.isNotEmpty) {
      throw CliException(
        '環境変数 ${missing.join(', ')} がありません。'
        '`op run --env-file=store/.env.store -- …` を付けて実行してください',
      );
    }
    return AscCredentials(
      keyId: env['ASC_KEY_ID']!.trim(),
      issuerId: env['ASC_ISSUER_ID']!.trim(),
      privateKeyPem: env['ASC_PRIVATE_KEY']!,
    );
  }

  final String keyId;
  final String issuerId;
  final String privateKeyPem;

  @override
  String toString() => 'AscCredentials(keyId: $keyId)'; // 鍵は出さない
}

/// トークンの有効期間。Appleの上限は20分。時計のずれを見込んで短めにする。
const ascTokenLifetime = Duration(minutes: 15);

/// App Store Connect API 用のJWTを作る。
///
/// ヘッダ: `alg: ES256`, `kid`, `typ: JWT`
/// クレーム: `iss`(Issuer ID), `iat`, `exp`, `aud: appstoreconnect-v1`
String buildAscJwt(AscCredentials credentials, {required DateTime now}) {
  final iat = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  final exp = iat + ascTokenLifetime.inSeconds;
  final jwt = JWT(
    {
      'iss': credentials.issuerId,
      'iat': iat,
      'exp': exp,
      'aud': 'appstoreconnect-v1',
    },
    header: {'kid': credentials.keyId, 'typ': 'JWT'},
  );
  try {
    // iat/exp は上で入れたので、ライブラリに現在時刻で上書きさせない。
    return jwt.sign(
      ECPrivateKey(credentials.privateKeyPem),
      algorithm: JWTAlgorithm.ES256,
      noIssueAt: true,
    );
  } on Object catch (e) {
    throw CliException('ASC_PRIVATE_KEY を .p8 の秘密鍵として読めません: $e');
  }
}
