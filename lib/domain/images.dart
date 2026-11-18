/// ストアに載せる画像(Playのアイコン・フィーチャーグラフィック・
/// スクリーンショット、ASCのスクリーンショット)の型と、比較・検査に使う純関数。
library;

import 'dart:typed_data';

/// `store/` 配下の画像ファイル1枚。並び順はファイル名の昇順。
final class LocalImage {
  const LocalImage({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// 画像の縦横のピクセル数。
typedef ImageSize = ({int width, int height});

/// Google Play の画像の種類(`edits.images` の `imageType`)。
///
/// 1枚だけの種類は `store/play/<言語>/images/<apiName>.png`、
/// 複数枚の種類は `store/play/<言語>/images/<apiName>/` 配下に置く。
enum PlayImageType {
  icon('icon', maxCount: 1, exactSize: (width: 512, height: 512)),
  featureGraphic(
    'featureGraphic',
    maxCount: 1,
    exactSize: (width: 1024, height: 500),
  ),
  phoneScreenshots('phoneScreenshots', maxCount: 8);

  const PlayImageType(this.apiName, {required this.maxCount, this.exactSize});

  final String apiName;
  final int maxCount;

  /// 寸法が決まっている種類だけ持つ。スクリーンショットは範囲で検査する。
  final ImageSize? exactSize;

  bool get isSingle => maxCount == 1;
}

/// PNGのヘッダ(IHDR)から縦横を読む。PNGでなければ null。
///
/// ストアへはPNGだけを置く規約にする(JPEGは再圧縮で画質が落ちるうえ、
/// 寸法の読み取りにJPEGのマーカー解析まで抱えるほどの利点がない)。
ImageSize? pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  // 8バイトの署名の直後が IHDR チャンク(長さ4 + 種別4 + 幅4 + 高さ4)。
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

/// PNGがアルファチャンネルを持つか(IHDRのカラータイプが 4=グレー+α / 6=RGBA)。
/// PNGでなければ null。
///
/// Google Play のスクリーンショット・フィーチャーグラフィックは、アルファの無い
/// 24bit PNG しか受け付けない。
bool? pngHasAlpha(Uint8List bytes) {
  if (pngSize(bytes) == null || bytes.length < 26) return null;
  final int colorType = bytes[25];
  return colorType == 4 || colorType == 6;
}

/// 画像の並びがストア側と同じかどうか。
///
/// ストアが返すダウンロード用の画像は再圧縮されていて元ファイルと一致しない。
/// そのため比べるのはバイト列ではなく、アップロード時のハッシュ
/// (PlayはSHA-256、ASCはMD5)の並びにする。順番が違うのも差分として扱う
/// (スクリーンショットは並び順がそのまま表示順になるため)。
bool sameImageSequence(List<String> localHashes, List<String?> remoteHashes) {
  if (localHashes.length != remoteHashes.length) return false;
  for (var i = 0; i < localHashes.length; i++) {
    if (localHashes[i].toLowerCase() != remoteHashes[i]?.toLowerCase()) {
      return false;
    }
  }
  return true;
}
