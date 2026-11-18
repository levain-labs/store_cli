/// 端末への表示(差分・検査結果)。ストアに依存しない共通部分。
library;

import 'dart:io';

import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/domain/diff.dart';
import 'package:store_cli/domain/limits.dart';
import 'package:store_cli/domain/listing.dart';

/// 検査で違反があれば一覧を出して止める(APIは叩かない)。
void throwIfViolations(List<LimitViolation> violations) {
  if (violations.isEmpty) return;
  throw CliException(
    [
      '上限を超えている項目があります。何も送らずに終了します:',
      for (final v in violations) '  - ${describeViolation(v)}',
    ].join('\n'),
  );
}

/// テキスト項目の比較結果を表示し、変更の件数を返す。
int printFieldChanges<F extends TextFieldSpec>(
  String prefix,
  List<FieldChange<F>> changes,
) {
  var count = 0;
  for (final change in changes) {
    switch (change) {
      case Unchanged(:final field):
        stdout.writeln('$prefix ${field.label}: 変更なし');
      case Changed(:final field, :final remote, :final local):
        count++;
        stdout.writeln(
          '$prefix ${field.label}: 変更あり'
          '${remote == null ? '(ストアは未設定)' : ''}',
        );
        for (final line in formatLineDiff(lineDiff(remote ?? '', local))) {
          stdout.writeln(line);
        }
    }
  }
  return count;
}

/// dry-run の締めの一文。
void printDryRunFooter(int changeCount, {String applyHint = '--apply'}) {
  if (changeCount == 0) {
    stdout.writeln('変更はありません');
  } else {
    stdout.writeln('dry-run: $changeCount件の変更。反映するには $applyHint を付けてください');
  }
}
