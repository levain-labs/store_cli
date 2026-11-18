import 'dart:typed_data';

import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/limits.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:test/test.dart';

/// 寸法とカラータイプだけを持つ最小のPNGヘッダ
/// (署名8バイト + IHDRの長さ・種別・幅・高さ・ビット深度・カラータイプ)。
/// カラータイプの既定は 2(RGB。アルファ無し)。
Uint8List fakePng(int width, int height, {int colorType = 2}) {
  final bytes = Uint8List(26);
  bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final data = ByteData.sublistView(bytes)
    ..setUint32(8, 13)
    ..setUint32(16, width)
    ..setUint32(20, height);
  bytes.setAll(12, 'IHDR'.codeUnits);
  bytes[24] = 8;
  bytes[25] = colorType;
  return data.buffer.asUint8List();
}

LocalImage png(String name, int w, int h) =>
    LocalImage(fileName: name, bytes: fakePng(w, h));

void main() {
  group('characterCount', () {
    test('日本語は1文字1字、絵文字(サロゲートペア)も1字', () {
      expect(characterCount('ラベル'), 3);
      expect(characterCount('🍞'), 1);
    });
  });

  group('checkTextLimits', () {
    test('上限ちょうどは通す', () {
      expect(checkTextLimits({PlayTextField.title: 'あ' * 30}), isEmpty);
    });

    test('上限を1字でも超えたら違反', () {
      final v = checkTextLimits({PlayTextField.title: 'あ' * 31}).single;
      expect(describeViolation(v), 'アプリ名: 31字(上限30字)');
    });

    test('上限の無い項目(URL)は見ない', () {
      expect(checkTextLimits({AscTextField.supportUrl: 'x' * 1000}), isEmpty);
    });
  });

  group('checkAscCharacters', () {
    test('ASCが拒否した文字(→)を含む項目を挙げる', () {
      final v = checkAscCharacters({
        AscTextField.promotionalText: '「えらぶ→枚数→印刷」',
        AscTextField.subtitle: '食品表示ラベル',
      });
      expect(v.map(describeViolation), ['プロモーションテキスト: 「→」はストアが受け付けません']);
    });
  });

  group('checkReleaseNotes', () {
    test('Playの上限は500字', () {
      expect(
        checkReleaseNotes('あ' * 500, label: 'r', max: playReleaseNotesMax),
        isNull,
      );
      expect(
        checkReleaseNotes('あ' * 501, label: 'r', max: playReleaseNotesMax),
        isA<TextTooLong>(),
      );
    });
  });

  group('pngSize', () {
    test('IHDRから縦横を読む', () {
      expect(pngSize(fakePng(1290, 2796)), (width: 1290, height: 2796));
    });

    test('PNGでなければ null', () {
      expect(pngSize(Uint8List.fromList(List.filled(30, 0xFF))), isNull);
      expect(pngSize(Uint8List(4)), isNull);
    });
  });

  group('checkPlayImages', () {
    test('アイコンは512×512ちょうど', () {
      expect(
        checkPlayImages(PlayImageType.icon, [png('icon.png', 512, 512)]),
        isEmpty,
      );
      final v = checkPlayImages(PlayImageType.icon, [
        png('icon.png', 1024, 1024),
      ]).single;
      expect(describeViolation(v), 'icon.png: 1024×1024(512×512であること)');
    });

    test('スクリーンショットは長辺が短辺の2倍まで', () {
      expect(
        checkPlayImages(PlayImageType.phoneScreenshots, [
          png('01.png', 1080, 2160),
        ]),
        isEmpty,
      );
      expect(
        checkPlayImages(PlayImageType.phoneScreenshots, [
          png('01.png', 1080, 2400),
        ]),
        [isA<BadImageSize>()],
      );
    });

    test('スクリーンショットは8枚まで', () {
      final images = [for (var i = 0; i < 9; i++) png('$i.png', 1080, 1920)];
      expect(checkPlayImages(PlayImageType.phoneScreenshots, images), [
        isA<TooManyImages>(),
      ]);
    });

    test('スクリーンショットはアルファ付き(RGBA)を弾く。アイコンは通す', () {
      final rgba = LocalImage(
        fileName: '01.png',
        bytes: fakePng(1080, 2160, colorType: 6),
      );
      expect(checkPlayImages(PlayImageType.phoneScreenshots, [rgba]), [
        isA<HasAlpha>(),
      ]);
      final icon = LocalImage(
        fileName: 'icon.png',
        bytes: fakePng(512, 512, colorType: 6),
      );
      expect(checkPlayImages(PlayImageType.icon, [icon]), isEmpty);
    });

    test('PNGでないものは違反', () {
      final notPng = LocalImage(fileName: 'a.png', bytes: Uint8List(30));
      expect(checkPlayImages(PlayImageType.phoneScreenshots, [notPng]), [
        isA<NotPng>(),
      ]);
    });
  });

  group('checkAscScreenshots', () {
    test('10枚まで・PNGであること', () {
      final ok = [for (var i = 0; i < 10; i++) png('$i.png', 1290, 2796)];
      expect(checkAscScreenshots('APP_IPHONE_67', ok), isEmpty);
      expect(
        checkAscScreenshots('APP_IPHONE_67', [...ok, png('x.png', 1, 1)]),
        [isA<TooManyImages>()],
      );
    });
  });

  group('sameImageSequence', () {
    test('同じハッシュが同じ順なら同じ(大文字小文字は区別しない)', () {
      expect(sameImageSequence(['ab', 'cd'], ['AB', 'cd']), isTrue);
    });

    test('順番が違えば差分(並び順が表示順になるため)', () {
      expect(sameImageSequence(['ab', 'cd'], ['cd', 'ab']), isFalse);
    });

    test('枚数が違えば差分。ストア側のハッシュ欠落も差分', () {
      expect(sameImageSequence(['ab'], ['ab', 'cd']), isFalse);
      expect(sameImageSequence(['ab'], [null]), isFalse);
    });
  });
}
