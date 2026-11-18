/// App Store Connect API のうち、このCLIが使うリソースだけを手書きした型。
///
/// 参照元はAppleが公開しているOpenAPI仕様(生成はしない。仕様が巨大で
/// 使うのは10種類ほどのため)。属性は欠けていても落ちないよう
/// すべて nullable で読む。
library;

import 'package:store_cli/domain/asc_targets.dart';
import 'package:store_cli/domain/listing.dart';

typedef Json = Map<String, dynamic>;

/// JSON:API の `data` の1件。
final class AscResource {
  const AscResource({
    required this.type,
    required this.id,
    required this.attributes,
  });

  factory AscResource.fromJson(Json json) => AscResource(
    type: json['type'] as String,
    id: json['id'] as String,
    attributes: (json['attributes'] as Json?) ?? const {},
  );

  final String type;
  final String id;
  final Json attributes;

  String? string(String key) => attributes[key] as String?;
}

/// JSON:API の関連の参照(`{"type": …, "id": …}`)。
Json ascRef(String type, String id) => {
  'data': {'type': type, 'id': id},
};

final class AscApp {
  AscApp.fromResource(AscResource r)
    : id = r.id,
      name = r.string('name'),
      bundleId = r.string('bundleId');

  final String id;
  final String? name;
  final String? bundleId;
}

/// アプリ情報(`appInfos`)。名前・サブタイトル等の「アプリ単位」の項目の入れ物。
final class AscAppInfo {
  AscAppInfo.fromResource(AscResource r)
    : id = r.id,
      // `appStoreState` は非推奨。新しい `state` を優先する。
      state = AscState.parse(r.string('state') ?? r.string('appStoreState'));

  final String id;
  final AscState state;

  AscVersioned get summary => (id: id, label: 'アプリ情報', state: state);
}

/// App Store のバージョン(`appStoreVersions`)。
final class AscVersion {
  AscVersion.fromResource(AscResource r)
    : id = r.id,
      versionString = r.string('versionString') ?? '?',
      // `appStoreState` は非推奨。新しい `appVersionState` を優先する。
      state = AscState.parse(
        r.string('appVersionState') ?? r.string('appStoreState'),
      ),
      createdDate = DateTime.tryParse(r.string('createdDate') ?? '');

  final String id;
  final String versionString;
  final AscState state;
  final DateTime? createdDate;

  AscVersioned get summary => (id: id, label: versionString, state: state);
}

/// `appInfoLocalizations` / `appStoreVersionLocalizations` の1言語分。
final class AscLocalization {
  AscLocalization.fromResource(AscResource r)
    : id = r.id,
      type = r.type,
      locale = r.string('locale'),
      attributes = r.attributes;

  final String id;
  final String type;
  final String? locale;
  final Json attributes;

  String? valueOf(AscTextField field) =>
      attributes[ascAttributeName(field)] as String?;

  String? get whatsNew => attributes['whatsNew'] as String?;
}

/// 掲載情報の項目と、APIの属性名の対応。
String ascAttributeName(AscTextField field) => switch (field) {
  AscTextField.name => 'name',
  AscTextField.subtitle => 'subtitle',
  AscTextField.privacyPolicyUrl => 'privacyPolicyUrl',
  AscTextField.description => 'description',
  AscTextField.keywords => 'keywords',
  AscTextField.supportUrl => 'supportUrl',
  AscTextField.marketingUrl => 'marketingUrl',
  AscTextField.promotionalText => 'promotionalText',
};

/// TestFlight にあるビルド(`builds`)。
final class AscBuild {
  AscBuild.fromResource(AscResource r)
    : id = r.id,
      version = r.string('version'),
      processingState = r.string('processingState');

  final String id;

  /// ビルド番号(CFBundleVersion)。
  final String? version;

  /// `PROCESSING` / `FAILED` / `INVALID` / `VALID`。
  final String? processingState;
}

/// スクリーンショットの組(画面サイズ種別ごと)。
final class AscScreenshotSet {
  AscScreenshotSet.fromResource(AscResource r)
    : id = r.id,
      displayType = r.string('screenshotDisplayType');

  final String id;
  final String? displayType;
}

/// スクリーンショット1枚。
final class AscScreenshot {
  AscScreenshot.fromResource(AscResource r)
    : id = r.id,
      fileName = r.string('fileName'),
      sourceFileChecksum = r.string('sourceFileChecksum'),
      uploadOperations = [
        for (final op
            in (r.attributes['uploadOperations'] as List<dynamic>?) ?? const [])
          AscUploadOperation.fromJson(op as Json),
      ];

  final String id;
  final String? fileName;

  /// アップロード確定時に送った元ファイルのMD5。並びの比較に使う。
  final String? sourceFileChecksum;

  /// 予約直後だけ返る、実体の送り先。
  final List<AscUploadOperation> uploadOperations;
}

/// 予約したスクリーンショットの実体の送り方(分割アップロードの1片)。
final class AscUploadOperation {
  AscUploadOperation.fromJson(Json json)
    : method = json['method'] as String,
      url = json['url'] as String,
      offset = json['offset'] as int,
      length = json['length'] as int,
      requestHeaders = {
        for (final h in (json['requestHeaders'] as List<dynamic>?) ?? const [])
          (h as Json)['name'] as String: h['value'] as String,
      };

  final String method;
  final String url;
  final int offset;
  final int length;
  final Map<String, String> requestHeaders;
}

/// 審査提出(`reviewSubmissions`)。
final class AscReviewSubmission {
  AscReviewSubmission.fromResource(AscResource r)
    : id = r.id,
      state = r.string('state');

  final String id;
  final String? state;
}
