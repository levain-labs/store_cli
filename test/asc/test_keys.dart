// テスト専用の使い捨て鍵(P-256)。どのApple/Googleアカウントにも登録していない。
// `openssl ecparam -name prime256v1 -genkey | openssl pkcs8 -topk8 -nocrypt` で生成した。
const testPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgEMYIQFZu6FbsAW4j
DN9XPHhHdx+Lcwfnm0DFtF0/pz6hRANCAARQhL+qZiISfqdxk3mzcAOjAaw1cPE3
PIzM4tlPdU6wxGQH5QSGuN2PzSYpxCDoA9sDHGeOkuEJ8Vn4cNfm8kvC
-----END PRIVATE KEY-----
''';

const testPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEUIS/qmYiEn6ncZN5s3ADowGsNXDx
NzyMzOLZT3VOsMRkB+UEhrjdj80mKcQg6APbAxxnjpLhCfFZ+HDX5vJLwg==
-----END PUBLIC KEY-----
''';
