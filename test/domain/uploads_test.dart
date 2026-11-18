import 'package:store_cli/domain/uploads.dart';
import 'package:test/test.dart';

void main() {
  group('checkNewBuildNumber', () {
    test('ストアに何も無ければ通す', () {
      expect(checkNewBuildNumber([], 1), isNull);
    });

    test('最大より大きければ通す(間が空いていてもよい)', () {
      expect(checkNewBuildNumber([3, 7, 5], 10), isNull);
    });

    test('最大と同じなら止める', () {
      expect(checkNewBuildNumber([3, 7], 7), contains('最大の番号 7 以下'));
    });

    test('最大より小さければ、使っていない番号でも止める', () {
      expect(checkNewBuildNumber([3, 7], 4), contains('最大の番号 7 以下'));
    });

    test('0以下は止める', () {
      expect(checkNewBuildNumber([], 0), contains('1以上'));
    });
  });

  test('altoolUploadArgs: 鍵はファイルのパスで渡し、鍵の中身は引数に載せない', () {
    final args = altoolUploadArgs(
      ipaPath: '/b/a.ipa',
      appleId: '1234567890',
      bundleId: 'com.example.app',
      versionName: '0.1.0',
      buildNumber: '12',
      keyId: 'KEY',
      issuerId: 'ISSUER',
      p8Path: '/tmp/x/AuthKey_KEY.p8',
    );
    expect(args.first, 'altool');
    expect(args.sublist(1, 3), ['--upload-package', '/b/a.ipa']);
    String valueOf(String flag) => args[args.indexOf(flag) + 1];
    expect(valueOf('--apple-id'), '1234567890');
    expect(valueOf('--bundle-version'), '12');
    expect(valueOf('--bundle-short-version-string'), '0.1.0');
    expect(valueOf('--p8-file-path'), '/tmp/x/AuthKey_KEY.p8');
    expect(args, isNot(contains('--auth-string')));
  });
}
