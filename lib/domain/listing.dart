/// ストアの掲載情報のうち、`store/` 配下で「1ファイル1項目」のテキストとして
/// 管理する項目の定義。
///
/// 字数の上限は各ストアのコンソールの表示に合わせている。超えた値はAPIを
/// 叩く前に `limits.dart` が止める(サーバー側のエラーより読みやすいため)。
library;

/// 1ファイル1項目のテキスト項目。
abstract interface class TextFieldSpec {
  /// `store/<ストア>/<言語>/` 配下のファイル名。
  String get fileName;

  /// 差分・検査の出力に使う日本語の表示名。
  String get label;

  /// 文字数の上限。上限の定めが無い項目(URL)は null。
  int? get maxLength;
}

/// Google Play のストアの掲載情報(`edits.listings`)。
enum PlayTextField implements TextFieldSpec {
  title('title.txt', 'アプリ名', 30),
  shortDescription('short_description.txt', '簡単な説明', 80),
  fullDescription('full_description.txt', '詳しい説明', 4000);

  const PlayTextField(this.fileName, this.label, this.maxLength);

  @override
  final String fileName;
  @override
  final String label;
  @override
  final int? maxLength;
}

/// App Store Connect の項目がどのリソースに保存されるか。
///
/// ASCの掲載情報は「アプリ単位」(`appInfoLocalizations`)と
/// 「バージョン単位」(`appStoreVersionLocalizations`)に分かれており、
/// どちらも審査に出していない版(編集可能な状態)でしか書き換えられない。
/// プロモーションテキストだけは公開中のバージョンでもいつでも書き換えられる。
enum AscScope { appInfo, version, anytime }

/// App Store Connect の掲載情報。
enum AscTextField implements TextFieldSpec {
  name('name.txt', '名前', 30, AscScope.appInfo),
  subtitle('subtitle.txt', 'サブタイトル', 30, AscScope.appInfo),
  privacyPolicyUrl('privacy_url.txt', 'プライバシーポリシーURL', null, AscScope.appInfo),
  description('description.txt', '説明', 4000, AscScope.version),
  keywords('keywords.txt', 'キーワード', 100, AscScope.version),
  supportUrl('support_url.txt', 'サポートURL', null, AscScope.version),
  marketingUrl('marketing_url.txt', 'マーケティングURL', null, AscScope.version),
  promotionalText('promotional_text.txt', 'プロモーションテキスト', 170, AscScope.anytime);

  const AscTextField(this.fileName, this.label, this.maxLength, this.scope);

  @override
  final String fileName;
  @override
  final String label;
  @override
  final int? maxLength;
  final AscScope scope;
}

/// ファイルとストアの値を比べる前にそろえる。
///
/// - 改行をLFにそろえる(Windowsで編集されたファイルでも差分にしない)
/// - 末尾の空白・改行を落とす(エディタが末尾に改行を足しても差分にしない)
///
/// 先頭や途中の空白は意味を持ちうるので触らない。
String normalizeText(String raw) =>
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();

/// ストアの字数の数え方に合わせ、UTF-16のコード単位ではなく
/// Unicodeのコードポイントで数える(絵文字を2文字と数えない)。
int characterCount(String text) => text.runes.length;
