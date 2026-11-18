import 'package:store_cli/domain/diff.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeText', () {
    test('末尾の改行・空白は差分にしない', () {
      expect(normalizeText('説明\n\n'), '説明');
      expect(normalizeText('説明  \n'), '説明');
    });

    test('CRLFはLFにそろえる', () {
      expect(normalizeText('1行目\r\n2行目\r\n'), '1行目\n2行目');
    });

    test('先頭や途中の空白は意味を持ちうるので残す', () {
      expect(normalizeText('  字下げ\n\n段落'), '  字下げ\n\n段落');
    });
  });

  group('diffFields', () {
    test('ファイルに無い項目は比べない(ストアの値を空にしない)', () {
      final changes = diffFields(
        local: {PlayTextField.title: 'サンプルアプリ'},
        remote: {
          PlayTextField.title: 'サンプルアプリ',
          PlayTextField.shortDescription: '既存の説明',
        },
      );
      expect(changes, hasLength(1));
      expect(changes.single, isA<Unchanged<PlayTextField>>());
    });

    test('末尾の改行の違いだけなら変更なし', () {
      final changes = diffFields(
        local: {PlayTextField.title: 'サンプルアプリ\n'},
        remote: {PlayTextField.title: 'サンプルアプリ'},
      );
      expect(changes.single, isA<Unchanged<PlayTextField>>());
    });

    test('値が違えば Changed(反映する値は正規化済み)', () {
      final changes = diffFields(
        local: {PlayTextField.title: '新しい名前\n'},
        remote: {PlayTextField.title: '古い名前'},
      );
      final change = changes.single as Changed<PlayTextField>;
      expect(change.remote, '古い名前');
      expect(change.local, '新しい名前');
    });

    test('ストアが未設定(null)なら Changed で remote は null', () {
      final changes = diffFields(
        local: {AscTextField.subtitle: '食品表示ラベル'},
        remote: {AscTextField.subtitle: null},
      );
      final change = changes.single as Changed<AscTextField>;
      expect(change.remote, isNull);
    });

    test('空のファイルは「空にする」意思として扱う', () {
      final changes = diffFields(
        local: {AscTextField.marketingUrl: ''},
        remote: {AscTextField.marketingUrl: 'https://example.com'},
      );
      expect((changes.single as Changed<AscTextField>).local, '');
    });
  });

  group('lineDiff', () {
    test('変わった行だけが削除+追加になる', () {
      final lines = lineDiff('A\nB\nC', 'A\nX\nC');
      expect(lines.map((l) => (l.runtimeType, l.text)), [
        (SameLine, 'A'),
        (RemovedLine, 'B'),
        (AddedLine, 'X'),
        (SameLine, 'C'),
      ]);
    });

    test('空から追加: 空の行を「変更なし」として混ぜない', () {
      final lines = lineDiff('', '1行目\n\n3行目');
      expect(lines.every((l) => l is AddedLine), isTrue);
      expect(lines.map((l) => l.text), ['1行目', '', '3行目']);
    });

    test('空へ削除', () {
      expect(lineDiff('1行目', '').every((l) => l is RemovedLine), isTrue);
    });
  });

  group('formatLineDiff', () {
    test('変更から離れた行は前後とも … で省略する', () {
      final before = List.generate(10, (i) => '行$i').join('\n');
      final after = before.replaceFirst('行5', '行5改');
      final out = formatLineDiff(lineDiff(before, after));
      expect(out, [
        '    …',
        '      行4',
        '    - 行5',
        '    + 行5改',
        '      行6',
        '    …',
      ]);
    });
  });
}
