import 'package:store_cli/domain/asc_targets.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:test/test.dart';

AscVersioned v(String id, AscState state) => (id: id, label: id, state: state);

void main() {
  group('AscState.parse', () {
    test('既知の値', () {
      expect(
        AscState.parse('PREPARE_FOR_SUBMISSION'),
        AscState.prepareForSubmission,
      );
      expect(
        AscState.parse('READY_FOR_DISTRIBUTION'),
        AscState.readyForDistribution,
      );
    });

    test('知らない値・null・空は unknown(編集不可)へ倒す', () {
      for (final raw in ['SOMETHING_NEW', null, '']) {
        final state = AscState.parse(raw);
        expect(state, AscState.unknown, reason: '$raw');
        expect(state.editable, isFalse);
        expect(state.live, isFalse);
      }
    });

    test('審査中・審査待ちは編集できない', () {
      expect(AscState.waitingForReview.editable, isFalse);
      expect(AscState.inReview.editable, isFalse);
    });

    test('旧属性の READY_FOR_SALE も公開中として扱う', () {
      expect(AscState.parse('READY_FOR_SALE').live, isTrue);
    });
  });

  group('AscSelection.targetFor', () {
    test('編集中の版があれば、アプリ単位・バージョン単位ともそこへ書く', () {
      final s = AscSelection.from(
        versions: [
          v('v2', AscState.prepareForSubmission),
          v('v1', AscState.readyForDistribution),
        ],
        appInfos: [
          v('i2', AscState.prepareForSubmission),
          v('i1', AscState.readyForDistribution),
        ],
      );
      expect(
        s.targetFor(AscTextField.name),
        isA<WriteToAppInfo>().having((t) => t.appInfo.id, 'id', 'i2'),
      );
      expect(
        s.targetFor(AscTextField.description),
        isA<WriteToVersion>().having((t) => t.version.id, 'id', 'v2'),
      );
      expect(
        s.targetFor(AscTextField.promotionalText),
        isA<WriteToVersion>().having((t) => t.version.id, 'id', 'v2'),
      );
    });

    test('公開中の版しか無ければ、プロモーションテキストだけ公開中の版へ書ける', () {
      final s = AscSelection.from(
        versions: [v('v1', AscState.readyForDistribution)],
        appInfos: [v('i1', AscState.readyForDistribution)],
      );
      expect(s.targetFor(AscTextField.name), isA<NotWritable>());
      expect(s.targetFor(AscTextField.description), isA<NotWritable>());
      expect(
        s.targetFor(AscTextField.promotionalText),
        isA<WriteToVersion>().having((t) => t.version.id, 'id', 'v1'),
      );
    });

    test('審査中の版には書かない', () {
      final s = AscSelection.from(
        versions: [
          v('v2', AscState.waitingForReview),
          v('v1', AscState.readyForDistribution),
        ],
        appInfos: [v('i1', AscState.readyForDistribution)],
      );
      expect(s.targetFor(AscTextField.keywords), isA<NotWritable>());
      expect(s.versionToRead?.id, 'v1');
    });

    test('pull は編集中 > 公開中の順で読む', () {
      final s = AscSelection.from(
        versions: [
          v('v2', AscState.prepareForSubmission),
          v('v1', AscState.readyForDistribution),
        ],
        appInfos: [v('i1', AscState.readyForDistribution)],
      );
      expect(s.versionToRead?.id, 'v2');
      expect(s.appInfoToRead?.id, 'i1');
    });

    test('版が1つも無ければ何も書けない', () {
      final s = AscSelection.from(versions: [], appInfos: []);
      for (final field in AscTextField.values) {
        expect(s.targetFor(field), isA<NotWritable>(), reason: field.name);
      }
    });
  });
}
