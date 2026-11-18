/// 利用者に見せて終了するエラー。`bin/store.dart` が標準エラーへ出して
/// 終了コード1で終わる(スタックトレースは出さない)。
///
/// 想定外の例外はこれに包まず、そのまま上へ投げてスタックトレースごと見せる。
final class CliException implements Exception {
  CliException(this.message);

  final String message;

  @override
  String toString() => message;
}
