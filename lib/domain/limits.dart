/// APIを叩く前にローカルで行う検査。1件でも違反があれば何も送らずに止める。
library;

import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/listing.dart';

/// App Store Connect が受け付けなかった文字。APIが409で拒否したものを足していく
/// (Appleは一覧を公開していないため、実際に弾かれた文字だけを載せる)。
///
/// - `→`: プロモーションテキストで拒否された(2026-10-13)。説明文で通るかは未確認だが、
///   どの項目でも使わない規律にする
const ascRejectedCharacters = ['→'];

/// 検査で見つかった違反。表示は [describeViolation] で行う。
sealed class LimitViolation {
  const LimitViolation();
}

/// テキストが字数の上限を超えている。
final class TextTooLong extends LimitViolation {
  const TextTooLong({
    required this.label,
    required this.actual,
    required this.max,
  });

  final String label;
  final int actual;
  final int max;
}

/// 画像の枚数が上限を超えている。
final class TooManyImages extends LimitViolation {
  const TooManyImages({
    required this.label,
    required this.actual,
    required this.max,
  });

  final String label;
  final int actual;
  final int max;
}

/// ストアが受け付けない文字を含んでいる。
final class RejectedCharacter extends LimitViolation {
  const RejectedCharacter({required this.label, required this.character});

  final String label;
  final String character;
}

/// PNGとして読めない画像。
final class NotPng extends LimitViolation {
  const NotPng({required this.fileName});

  final String fileName;
}

/// アルファチャンネルを持つPNG(Google Play は受け付けない)。
final class HasAlpha extends LimitViolation {
  const HasAlpha({required this.fileName});

  final String fileName;
}

/// 寸法の要件を満たさない画像。
final class BadImageSize extends LimitViolation {
  const BadImageSize({
    required this.fileName,
    required this.actual,
    required this.requirement,
  });

  final String fileName;
  final ImageSize actual;

  /// 要件の説明(例: `512×512`、`各辺320〜3840px`)。
  final String requirement;
}

String describeViolation(LimitViolation v) => switch (v) {
  TextTooLong(:final label, :final actual, :final max) =>
    '$label: $actual字(上限$max字)',
  TooManyImages(:final label, :final actual, :final max) =>
    '$label: $actual枚(上限$max枚)',
  RejectedCharacter(:final label, :final character) =>
    '$label: 「$character」はストアが受け付けません',
  NotPng(:final fileName) => '$fileName: PNGではありません',
  HasAlpha(:final fileName) =>
    '$fileName: アルファ(透過)付きのPNGです。Google Play は受け付けません(RGBに変換してください)',
  BadImageSize(:final fileName, :final actual, :final requirement) =>
    '$fileName: ${actual.width}×${actual.height}($requirement)',
};

/// テキスト項目の字数検査。値が無い(ファイルが無い=管理しない)項目は見ない。
List<LimitViolation> checkTextLimits<F extends TextFieldSpec>(
  Map<F, String> values,
) => [
  for (final MapEntry(key: field, value: text) in values.entries)
    if (field.maxLength case final max?)
      if (characterCount(text) > max)
        TextTooLong(label: field.label, actual: characterCount(text), max: max),
];

/// App Store Connect のテキスト項目に、受け付けない文字が無いかの検査。
List<LimitViolation> checkAscCharacters(Map<AscTextField, String> values) => [
  for (final MapEntry(key: field, value: text) in values.entries)
    for (final character in ascRejectedCharacters)
      if (text.contains(character))
        RejectedCharacter(label: field.label, character: character),
];

/// リリースノートの字数検査。上限はストアごとに違う(Play 500字 / ASC 4000字)。
LimitViolation? checkReleaseNotes(
  String text, {
  required String label,
  required int max,
}) {
  final count = characterCount(text);
  return count > max
      ? TextTooLong(label: label, actual: count, max: max)
      : null;
}

/// Google Play のリリースノートの上限。両ストアで同じファイルを使うため、
/// 実質これがリリースノートの上限になる。
const playReleaseNotesMax = 500;

/// App Store Connect の「このバージョンの新機能」の上限。
const ascReleaseNotesMax = 4000;

/// Google Play の画像の検査。
List<LimitViolation> checkPlayImages(
  PlayImageType type,
  List<LocalImage> images,
) {
  final violations = <LimitViolation>[];
  if (images.length > type.maxCount) {
    violations.add(
      TooManyImages(
        label: type.apiName,
        actual: images.length,
        max: type.maxCount,
      ),
    );
  }
  for (final image in images) {
    final size = pngSize(image.bytes);
    if (size == null) {
      violations.add(NotPng(fileName: image.fileName));
      continue;
    }
    // アイコンは透過を受け付けるが、スクリーンショット・フィーチャーグラフィックは不可。
    if (type != PlayImageType.icon && (pngHasAlpha(image.bytes) ?? false)) {
      violations.add(HasAlpha(fileName: image.fileName));
    }
    if (type.exactSize case final exact?) {
      if (size != exact) {
        violations.add(
          BadImageSize(
            fileName: image.fileName,
            actual: size,
            requirement: '${exact.width}×${exact.height}であること',
          ),
        );
      }
      continue;
    }
    // スクリーンショット: 各辺320〜3840px、長辺は短辺の2倍まで。
    final shorter = size.width < size.height ? size.width : size.height;
    final longer = size.width < size.height ? size.height : size.width;
    if (shorter < 320 || longer > 3840 || longer > shorter * 2) {
      violations.add(
        BadImageSize(
          fileName: image.fileName,
          actual: size,
          requirement: '各辺320〜3840px・長辺は短辺の2倍まで',
        ),
      );
    }
  }
  return violations;
}

/// App Store Connect のスクリーンショットの検査(1つの画面サイズ種別あたり)。
///
/// 画面サイズ種別ごとの許容寸法は種類が多く改定も多いため、ここでは
/// 枚数とPNGであることだけを見て、寸法はASC側の検査に任せる。
List<LimitViolation> checkAscScreenshots(
  String displayType,
  List<LocalImage> images,
) => [
  if (images.length > 10)
    TooManyImages(label: displayType, actual: images.length, max: 10),
  for (final image in images)
    if (pngSize(image.bytes) == null) NotPng(fileName: image.fileName),
];
