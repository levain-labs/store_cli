/// 境界: Google Play Developer API v3 の `pull` / `push` / `submit`。
///
/// Playは変更を1つの「編集(edit)」にまとめてから確定する、トランザクション型の
/// API。dry-run でも実際に編集へ変更を積んでから `edits.validate` で
/// サーバー側の検査を通し、確定(commit)せずに破棄する。手元の検査より
/// 一段確かな dry-run になる。
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:googleapis/androidpublisher/v3.dart';

import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/domain/diff.dart';
import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/limits.dart';
import 'package:store_cli/domain/uploads.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:store_cli/report.dart';
import 'package:store_cli/store_files.dart';

const _prefix = '[play]';

final class PlayCommands {
  PlayCommands(this._api, this._files);

  final AndroidPublisherApi _api;
  final StoreFiles _files;

  /// `store.yaml` の `play.package_name`。
  String get playPackageName => _files.config.play.packageName;

  /// `store.yaml` の `play.language`。
  String get _language => _files.playLanguage;

  /// いま実行中のAPI呼び出しの説明。失敗したとき、どの手順で落ちたかを示す
  /// (Playの403/400は本文が短く、どの呼び出しか分からないため)。
  String _step = '';

  /// ストアの掲載情報(テキスト)を `store/play/` へ書き出す。
  ///
  /// 画像は取り込まない。ストアが返すのはプレビュー用に再圧縮された画像で、
  /// 元ファイルとハッシュが一致せず、次の `push` が全画像を差分と見なすため。
  Future<void> pull() => _withEdit((editId) async {
    final listing = await _getListing(editId);
    if (listing == null) {
      stdout.writeln('$_prefix $_language の掲載情報がストアにありません');
      return false;
    }
    final written = _files.writePlayText({
      PlayTextField.title: listing.title,
      PlayTextField.shortDescription: listing.shortDescription,
      PlayTextField.fullDescription: listing.fullDescription,
    });
    for (final path in written) {
      stdout.writeln('$_prefix 書き出しました: $path');
    }
    stdout.writeln(
      '$_prefix 画像は取り込みません(ストアが返す画像は再圧縮されていて元ファイルと一致しないため)。'
      '管理する場合は元画像を store/play/$_language/images/ に置いてください',
    );
    return false;
  });

  /// `store/play/` の内容をストアへ反映する。[apply] が false なら dry-run。
  Future<void> push({required bool apply}) async {
    final localText = _files.readPlayText();
    final localImages = {
      for (final type in PlayImageType.values)
        type: ?_files.readPlayImages(type),
    };
    throwIfViolations([
      ...checkTextLimits(localText),
      for (final MapEntry(key: type, value: images) in localImages.entries)
        ...checkPlayImages(type, images),
    ]);

    await _withEdit((editId) async {
      final remote = await _getListing(editId);
      final textChanges = diffFields(
        local: localText,
        remote: {
          PlayTextField.title: remote?.title,
          PlayTextField.shortDescription: remote?.shortDescription,
          PlayTextField.fullDescription: remote?.fullDescription,
        },
      );
      var changeCount = printFieldChanges('$_prefix $_language /', textChanges);

      final changedImageTypes = <PlayImageType>[];
      for (final MapEntry(key: type, value: images) in localImages.entries) {
        _step = '画像の一覧の取得(edits.images.list)';
        final remoteImages = await _api.edits.images.list(
          playPackageName,
          editId,
          _language,
          type.apiName,
        );
        final remoteHashes = [
          for (final image in remoteImages.images ?? <Image>[]) image.sha256,
        ];
        final localHashes = [
          for (final image in images) sha256.convert(image.bytes).toString(),
        ];
        if (sameImageSequence(localHashes, remoteHashes)) {
          stdout.writeln('$_prefix 画像 ${type.apiName}: 変更なし');
        } else {
          changeCount++;
          changedImageTypes.add(type);
          stdout.writeln(
            '$_prefix 画像 ${type.apiName}: 変更あり'
            '(ストア${remoteHashes.length}枚 → ファイル${images.length}枚。全枚を差し替えます)',
          );
        }
      }

      if (changeCount == 0) {
        printDryRunFooter(0);
        return false;
      }

      // ここから編集へ変更を積む(dry-run でも積んでからサーバーに検査させる)。
      if (textChanges.any((c) => c is Changed)) {
        _step = '掲載情報の更新(edits.listings.update)';
        await _api.edits.listings.update(
          Listing(
            language: _language,
            title: localText[PlayTextField.title] ?? remote?.title,
            shortDescription:
                localText[PlayTextField.shortDescription] ??
                remote?.shortDescription,
            fullDescription:
                localText[PlayTextField.fullDescription] ??
                remote?.fullDescription,
            // update は掲載情報を丸ごと置き換えるため、管理していない動画URLは引き継ぐ。
            video: remote?.video,
          ),
          playPackageName,
          editId,
          _language,
        );
      }
      for (final type in changedImageTypes) {
        _step = '画像の削除(edits.images.deleteall)';
        await _api.edits.images.deleteall(
          playPackageName,
          editId,
          _language,
          type.apiName,
        );
        for (final image in localImages[type]!) {
          _step = '画像のアップロード(edits.images.upload)';
          await _api.edits.images.upload(
            playPackageName,
            editId,
            _language,
            type.apiName,
            uploadMedia: Media(
              Stream.value(image.bytes),
              image.bytes.length,
              contentType: 'image/png',
            ),
          );
        }
      }
      _step = 'Playの検査(edits.validate)';
      await _api.edits.validate(playPackageName, editId);
      stdout.writeln('$_prefix Playの検査(edits.validate)を通りました');

      if (!apply) {
        printDryRunFooter(changeCount);
        return false;
      }
      return true;
    }, onCommitted: () => stdout.writeln('$_prefix 反映しました'));
  }

  /// 内部テストにある [versionCode] を本番トラックへ出す。
  ///
  /// [send] が false なら下書き(`draft`。Play Consoleで最終確認してから送る)、
  /// true なら `completed`(確定と同時に審査へ送られる)。
  Future<void> submit({
    required String versionName,
    required int versionCode,
    required bool apply,
    required bool send,
  }) async {
    final notes = _files.readReleaseNotes(versionName);
    throwIfViolations([
      ?checkReleaseNotes(
        notes,
        label: 'リリースノート($versionName)',
        max: playReleaseNotesMax,
      ),
    ]);

    await _withEdit(
      (editId) async {
        _step = '内部テストのトラックの取得(edits.tracks.get)';
        final internal = await _api.edits.tracks.get(
          playPackageName,
          editId,
          'internal',
        );
        final release = [
          for (final r in internal.releases ?? <TrackRelease>[])
            if (r.versionCodes?.contains('$versionCode') ?? false) r,
        ].firstOrNull;
        if (release == null) {
          throw CliException(
            '内部テストのトラックに versionCode $versionCode が見つかりません。'
            '先にAABを内部テストへアップロードしてください',
          );
        }
        if (!(release.name?.contains(versionName) ?? false)) {
          stderr.writeln(
            '$_prefix 注意: 内部テストのリリース名「${release.name}」に $versionName が含まれていません。'
            'バージョン名の指定が正しいか確認してください',
          );
        }

        final status = send ? 'completed' : 'draft';
        stdout
          ..writeln(
            '$_prefix 本番トラックへ: versionCode $versionCode / $versionName / status=$status',
          )
          ..writeln('$_prefix リリースノート:')
          ..writeln(notes.split('\n').map((l) => '    $l').join('\n'));

        _step = '本番トラックの更新(edits.tracks.update)';
        await _api.edits.tracks.update(
          Track(
            track: 'production',
            releases: [
              TrackRelease(
                name: versionName,
                versionCodes: ['$versionCode'],
                status: status,
                releaseNotes: [LocalizedText(language: _language, text: notes)],
              ),
            ],
          ),
          playPackageName,
          editId,
          'production',
        );
        _step = 'Playの検査(edits.validate)';
        await _api.edits.validate(playPackageName, editId);
        stdout.writeln('$_prefix Playの検査(edits.validate)を通りました');

        if (!apply) {
          stdout.writeln('dry-run: 反映するには --apply を付けてください(審査へ送るには --send も)');
          return false;
        }
        return true;
      },
      onCommitted: () => stdout.writeln(
        send
            ? '$_prefix 本番トラックへ送りました(審査に入ります)'
            : '$_prefix 下書きを作成しました。Play Consoleの「本番」から内容を確認して審査へ送ってください',
      ),
    );
  }

  /// [aab] を内部テストのトラックへ出す(使う側のリリーススクリプトから呼ぶ)。
  ///
  /// dry-run ではアップロードせず、[versionCode] がストアにある最大の versionCode
  /// より大きいことだけを確かめる(ビルドの前に呼び、認証と番号の誤りで
  /// 長いビルドを無駄にしないため)。そのため dry-run では [aab] が無くてよい。
  Future<void> upload({
    required File aab,
    required String versionName,
    required int versionCode,
    required bool apply,
  }) async {
    if (apply && !aab.existsSync()) {
      throw CliException('AABがありません: ${aab.path}');
    }
    await _withEdit(
      (editId) async {
        _step = 'アップロード済みのAABの一覧の取得(edits.bundles.list)';
        final bundles = await _api.edits.bundles.list(playPackageName, editId);
        final problem = checkNewBuildNumber([
          for (final b in bundles.bundles ?? <Bundle>[]) ?b.versionCode,
        ], versionCode);
        if (problem != null) throw CliException(problem);
        stdout.writeln('$_prefix versionCode $versionCode はまだ使われていません');

        if (!apply) {
          stdout.writeln('dry-run: アップロードするには --apply を付けてください');
          return false;
        }

        _step = 'AABのアップロード(edits.bundles.upload)';
        stdout.writeln('$_prefix アップロードしています: ${aab.path}');
        final bundle = await _api.edits.bundles.upload(
          playPackageName,
          editId,
          uploadMedia: Media(
            aab.openRead(),
            aab.lengthSync(),
            contentType: 'application/octet-stream',
          ),
          uploadOptions: ResumableUploadOptions(),
        );
        if (bundle.versionCode != versionCode) {
          throw CliException(
            'アップロードしたAABの versionCode が ${bundle.versionCode} でした(期待: $versionCode)。'
            '何も確定せずに終了します',
          );
        }

        _step = '内部テストのトラックの更新(edits.tracks.update)';
        await _api.edits.tracks.update(
          Track(
            track: 'internal',
            releases: [
              // submit は内部テストのリリース名にバージョン名が含まれるかを確かめる。
              TrackRelease(
                name: '$versionName ($versionCode)',
                versionCodes: ['$versionCode'],
                status: 'completed',
              ),
            ],
          ),
          playPackageName,
          editId,
          'internal',
        );
        _step = 'Playの検査(edits.validate)';
        await _api.edits.validate(playPackageName, editId);
        return true;
      },
      onCommitted: () =>
          stdout.writeln('$_prefix 内部テストへ出しました: $versionName ($versionCode)'),
    );
  }

  /// 掲載情報を取得する。その言語の掲載情報がまだ無ければ null。
  Future<Listing?> _getListing(String editId) async {
    try {
      _step = '掲載情報の取得(edits.listings.get)';
      return await _api.edits.listings.get(playPackageName, editId, _language);
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// 編集(edit)を開いて [body] を実行し、[body] が true を返したときだけ確定する。
  /// それ以外(false・例外)は必ず破棄し、編集を開いたまま残さない。
  Future<void> _withEdit(
    Future<bool> Function(String editId) body, {
    void Function()? onCommitted,
  }) async {
    _step = '編集の作成(edits.insert)';
    final AppEdit edit;
    try {
      edit = await _api.edits.insert(AppEdit(), playPackageName);
    } on DetailedApiRequestError catch (e) {
      throw PlayApiException(_step, e);
    }
    final editId = edit.id!;
    var committed = false;
    try {
      if (await body(editId)) {
        _step = '編集の確定(edits.commit)';
        await _api.edits.commit(playPackageName, editId);
        committed = true;
        onCommitted?.call();
      }
    } on DetailedApiRequestError catch (e) {
      throw PlayApiException(_step, e);
    } finally {
      if (!committed) {
        try {
          await _api.edits.delete(playPackageName, editId);
        } on Object catch (e) {
          // 破棄の失敗で元の例外を隠さないよう、ここでは投げ直さない。
          // 確定していない編集はPlay側で一定時間後に失効するため実害はない。
          stderr.writeln('$_prefix 編集(edit $editId)の破棄に失敗しました(放置しても失効します): $e');
        }
      }
    }
  }
}

/// Play Developer API のエラーに、失敗した手順を添えたもの。
final class PlayApiException implements Exception {
  PlayApiException(this.step, this.error);

  /// 失敗したAPI呼び出しの説明(例: 掲載情報の更新(edits.listings.update))。
  final String step;
  final DetailedApiRequestError error;

  @override
  String toString() => [
    'Play Developer API がエラーを返しました: $step → ${error.status} ${error.message}',
    for (final e in error.errors) '  - ${e.reason}: ${e.message}',
    if (error.status == 403)
      '  権限が足りない可能性があります。Play Console の「ユーザーと権限」で '
          'play-publisher@ の権限を確認してください(付けた直後は反映まで時間がかかることがあります)',
  ].join('\n');
}
