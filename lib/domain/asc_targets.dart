/// App Store Connect で「どの版のどのリソースへ書くか」を決める純関数。
///
/// ASCの掲載情報は、審査に出していない版(編集可能な状態)でしか書き換えられない。
/// 状態の判定を誤ると、審査中や公開中の版へ書き込もうとしてAPIエラーになるか、
/// 逆に書けるはずの版を見落とす。判断をここに集めてテストで固める。
library;

import 'package:store_cli/domain/listing.dart';

/// `appStoreVersions` の `appVersionState`(旧 `appStoreState`)と
/// `appInfos` の `state`(旧 `appStoreState`)の値。
///
/// Appleが値を増やしても誤って書き込まないよう、知らない値は [unknown]
/// (編集不可)へ倒す。
enum AscState {
  prepareForSubmission('PREPARE_FOR_SUBMISSION', editable: true),
  developerRejected('DEVELOPER_REJECTED', editable: true),
  rejected('REJECTED', editable: true),
  metadataRejected('METADATA_REJECTED', editable: true),
  // 新しい審査提出(reviewSubmissions)で、提出物に入れたがまだ送っていない状態。
  readyForReview('READY_FOR_REVIEW', editable: true),
  waitingForReview('WAITING_FOR_REVIEW'),
  inReview('IN_REVIEW'),
  invalidBinary('INVALID_BINARY'),
  waitingForExportCompliance('WAITING_FOR_EXPORT_COMPLIANCE'),
  accepted('ACCEPTED'),
  pendingDeveloperRelease('PENDING_DEVELOPER_RELEASE'),
  pendingAppleRelease('PENDING_APPLE_RELEASE'),
  pendingRelease('PENDING_RELEASE'),
  processingForDistribution('PROCESSING_FOR_DISTRIBUTION'),
  readyForDistribution('READY_FOR_DISTRIBUTION', live: true),
  // 旧属性 appStoreState での公開中の値。
  readyForSale('READY_FOR_SALE', live: true),
  replacedWithNewVersion('REPLACED_WITH_NEW_VERSION'),
  replacedWithNewInfo('REPLACED_WITH_NEW_INFO'),
  unknown('');

  const AscState(this.raw, {this.editable = false, this.live = false});

  final String raw;

  /// 掲載情報を書き換えられる状態か。
  final bool editable;

  /// ストアで公開中の版か。
  final bool live;

  static AscState parse(String? raw) => AscState.values.firstWhere(
    (s) => s != unknown && s.raw == raw,
    orElse: () => unknown,
  );
}

/// 版(またはアプリ情報)の要約。APIのモデルからドメインへ渡すときの形。
typedef AscVersioned = ({String id, String label, AscState state});

/// 書き込み先の候補。
final class AscSelection {
  AscSelection._({
    required this.editableVersion,
    required this.liveVersion,
    required this.editableAppInfo,
    required this.liveAppInfo,
  });

  /// 版・アプリ情報の一覧から、編集可能なもの・公開中のものを1つずつ選ぶ。
  /// 一覧は新しい順(APIの既定の並び)で渡す。
  factory AscSelection.from({
    required List<AscVersioned> versions,
    required List<AscVersioned> appInfos,
  }) => AscSelection._(
    editableVersion: _firstWhereOrNull(versions, (v) => v.state.editable),
    liveVersion: _firstWhereOrNull(versions, (v) => v.state.live),
    editableAppInfo: _firstWhereOrNull(appInfos, (v) => v.state.editable),
    liveAppInfo: _firstWhereOrNull(appInfos, (v) => v.state.live),
  );

  final AscVersioned? editableVersion;
  final AscVersioned? liveVersion;
  final AscVersioned? editableAppInfo;
  final AscVersioned? liveAppInfo;

  /// `pull` で読む版。編集中の版があればそれ、無ければ公開中の版。
  AscVersioned? get versionToRead => editableVersion ?? liveVersion;

  /// `pull` で読むアプリ情報。
  AscVersioned? get appInfoToRead => editableAppInfo ?? liveAppInfo;

  /// 項目ごとの書き込み先。
  AscWriteTarget targetFor(AscTextField field) => switch (field.scope) {
    AscScope.appInfo => switch (editableAppInfo) {
      final info? => WriteToAppInfo(info),
      null => const NotWritable('編集中のアプリ情報がありません(新しいバージョンを作成すると編集できます)'),
    },
    AscScope.version => switch (editableVersion) {
      final version? => WriteToVersion(version),
      null => const NotWritable('編集中のバージョンがありません(新しいバージョンを作成すると編集できます)'),
    },
    // プロモーションテキストは公開中の版でも書き換えられる。編集中の版が
    // あればそちらへ書く(次のバージョンでも同じ文が引き継がれる)。
    AscScope.anytime => switch (editableVersion ?? liveVersion) {
      final version? => WriteToVersion(version),
      null => const NotWritable('バージョンがありません'),
    },
  };
}

/// 項目の書き込み先。
sealed class AscWriteTarget {
  const AscWriteTarget();
}

final class WriteToAppInfo extends AscWriteTarget {
  const WriteToAppInfo(this.appInfo);

  final AscVersioned appInfo;
}

final class WriteToVersion extends AscWriteTarget {
  const WriteToVersion(this.version);

  final AscVersioned version;
}

final class NotWritable extends AscWriteTarget {
  const NotWritable(this.reason);

  final String reason;
}

T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
