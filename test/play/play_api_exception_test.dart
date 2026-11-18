import 'package:googleapis/androidpublisher/v3.dart';
import 'package:store_cli/play/play_commands.dart';
import 'package:test/test.dart';

void main() {
  test('失敗した手順を添えて表示し、403なら権限の確認を促す', () {
    final e = PlayApiException(
      '掲載情報の更新(edits.listings.update)',
      DetailedApiRequestError(403, 'The caller does not have permission'),
    );
    final text = e.toString();
    expect(text, contains('掲載情報の更新(edits.listings.update) → 403'));
    expect(text, contains('play-publisher@ の権限を確認'));
  });

  test('403以外では権限の案内を出さない', () {
    final e = PlayApiException(
      'Playの検査(edits.validate)',
      DetailedApiRequestError(400, 'Invalid request'),
    );
    expect(e.toString(), isNot(contains('権限')));
  });
}
