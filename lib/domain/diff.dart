/// ファイル(正本)とストアの現在値の比較。
library;

import 'package:store_cli/domain/listing.dart';

/// 1項目の比較結果。
sealed class FieldChange<F extends TextFieldSpec> {
  const FieldChange(this.field);

  final F field;
}

final class Unchanged<F extends TextFieldSpec> extends FieldChange<F> {
  const Unchanged(super.field);
}

final class Changed<F extends TextFieldSpec> extends FieldChange<F> {
  const Changed(super.field, {required this.remote, required this.local});

  /// ストアの現在値。ストアに値が無ければ null。
  final String? remote;

  /// ファイルの値(反映後の値)。
  final String local;
}

/// ファイルにある項目だけを比べる。
///
/// ファイルが無い項目は「このリポジトリでは管理しない」とみなして比較対象から
/// 外す(誤ってストアの値を空にしないため)。値を空にしたいときは空のファイルを置く。
List<FieldChange<F>> diffFields<F extends TextFieldSpec>({
  required Map<F, String> local,
  required Map<F, String?> remote,
}) => [
  for (final MapEntry(key: field, value: localValue) in local.entries)
    switch (remote[field]) {
      final remoteValue?
          when normalizeText(remoteValue) == normalizeText(localValue) =>
        Unchanged(field),
      final remoteValue => Changed(
        field,
        remote: remoteValue,
        local: normalizeText(localValue),
      ),
    },
];

/// 行単位の差分の1行。
sealed class DiffLine {
  const DiffLine(this.text);

  final String text;
}

final class SameLine extends DiffLine {
  const SameLine(super.text);
}

final class RemovedLine extends DiffLine {
  const RemovedLine(super.text);
}

final class AddedLine extends DiffLine {
  const AddedLine(super.text);
}

/// 行単位の差分(最長共通部分列)。説明文は長くても数十行なので O(n×m) で足りる。
List<DiffLine> lineDiff(String before, String after) {
  // 空の文字列を「空行1行」として比べると、空の行が「変更なし」として紛れ込む。
  // 片方が空なら、もう片方を丸ごと追加(削除)として扱う。
  final a = _lines(before);
  final b = _lines(after);
  // lcs[i][j] = a[i..] と b[j..] の最長共通部分列の長さ
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final result = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      result.add(SameLine(a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      result.add(RemovedLine(a[i]));
      i++;
    } else {
      result.add(AddedLine(b[j]));
      j++;
    }
  }
  for (; i < a.length; i++) {
    result.add(RemovedLine(a[i]));
  }
  for (; j < b.length; j++) {
    result.add(AddedLine(b[j]));
  }
  return result;
}

List<String> _lines(String text) {
  final normalized = normalizeText(text);
  return normalized.isEmpty ? const [] : normalized.split('\n');
}

/// 差分を端末向けの文字列にする。変更のない行は前後 [context] 行だけ残す。
List<String> formatLineDiff(List<DiffLine> lines, {int context = 1}) {
  bool isChange(int index) => lines[index] is! SameLine;
  final keep = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (!isChange(i)) continue;
    for (var k = i - context; k <= i + context; k++) {
      if (k >= 0 && k < lines.length) keep[k] = true;
    }
  }
  final out = <String>[];
  var skipped = false;
  for (var i = 0; i < lines.length; i++) {
    if (!keep[i]) {
      skipped = true;
      continue;
    }
    if (skipped) out.add('    …');
    skipped = false;
    out.add(switch (lines[i]) {
      SameLine(:final text) => '      $text',
      RemovedLine(:final text) => '    - $text',
      AddedLine(:final text) => '    + $text',
    });
  }
  if (skipped) out.add('    …');
  return out;
}
