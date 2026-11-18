import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:store_cli/asc/asc_jwt.dart';
import 'package:store_cli/cli_exception.dart';
import 'package:test/test.dart';

import 'test_keys.dart';

void main() {
  const credentials = AscCredentials(
    keyId: 'KEY123',
    issuerId: 'issuer-uuid',
    privateKeyPem: testPrivateKeyPem,
  );

  group('buildAscJwt', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    final token = buildAscJwt(credentials, now: now);

    test('公開鍵で検証でき、ヘッダは ES256・kid・typ', () {
      final jwt = JWT.verify(
        token,
        ECPublicKey(testPublicKeyPem),
        checkExpiresIn: false,
      );
      expect(jwt.header, containsPair('alg', 'ES256'));
      expect(jwt.header, containsPair('kid', 'KEY123'));
      expect(jwt.header, containsPair('typ', 'JWT'));
    });

    test('クレームは iss・aud・iat・exp(有効期間はAppleの上限20分以内)', () {
      final payload = JWT.decode(token).payload as Map<String, dynamic>;
      final iat = now.millisecondsSinceEpoch ~/ 1000;
      expect(payload['iss'], 'issuer-uuid');
      expect(payload['aud'], 'appstoreconnect-v1');
      expect(payload['iat'], iat);
      expect(payload['exp'], iat + ascTokenLifetime.inSeconds);
      expect(ascTokenLifetime, lessThanOrEqualTo(const Duration(minutes: 20)));
    });

    test('秘密鍵として読めなければ利用者向けのエラー', () {
      const broken = AscCredentials(
        keyId: 'k',
        issuerId: 'i',
        privateKeyPem: 'not a key',
      );
      expect(() => buildAscJwt(broken, now: now), throwsA(isA<CliException>()));
    });
  });

  group('AscCredentials.fromEnvironment', () {
    test('足りない環境変数を全部挙げる', () {
      expect(
        () => AscCredentials.fromEnvironment({'ASC_KEY_ID': 'k'}),
        throwsA(
          isA<CliException>().having(
            (e) => e.message,
            'message',
            contains('ASC_ISSUER_ID, ASC_PRIVATE_KEY'),
          ),
        ),
      );
    });

    test('toString に鍵を出さない', () {
      expect(credentials.toString(), isNot(contains('PRIVATE KEY')));
    });
  });
}
