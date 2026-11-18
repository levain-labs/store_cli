/// 境界: App Store Connect API の `pull` / `push` / `submit`。
///
/// ASCには Play の `edits.validate` に当たるサーバー側の dry-run が無いため、
/// dry-run は手元の比較と検査だけを行い、何も書き込まない。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/domain/asc_targets.dart';
import 'package:store_cli/domain/diff.dart';
import 'package:store_cli/domain/images.dart';
import 'package:store_cli/domain/limits.dart';
import 'package:store_cli/domain/uploads.dart';
import 'package:store_cli/domain/listing.dart';
import 'package:store_cli/report.dart';
import 'package:store_cli/store_files.dart';
import 'package:store_cli/asc/asc_client.dart';
import 'package:store_cli/asc/asc_jwt.dart';
import 'package:store_cli/asc/asc_models.dart';

const _prefix = '[asc]';

/// 1回のコマンドで使う、アプリ・アプリ情報・バージョンの一覧。
final class _AppState {
  _AppState({required this.app, required this.appInfos, required this.versions})
    : selection = AscSelection.from(
        versions: [for (final v in versions) v.summary],
        appInfos: [for (final i in appInfos) i.summary],
      );

  final AscApp app;
  final List<AscAppInfo> appInfos;

  /// 新しい順。
  final List<AscVersion> versions;
  final AscSelection selection;
}

final class AscCommands {
  AscCommands(this._client, this._files, this._credentials);

  final AscClient _client;
  final StoreFiles _files;

  /// `store.yaml` の `asc.bundle_id`。
  String get ascBundleId => _files.config.asc.bundleId;

  /// `store.yaml` の `asc.locale`。
  String get _locale => _files.ascLocale;

  /// `upload` が altool へ鍵を渡すために使う(APIの呼び出しは [_client] が行う)。
  final AscCredentials _credentials;

  /// ストアの掲載情報(テキスト)を `store/asc/` へ書き出す。
  ///
  /// 編集中の版があればそれを、無ければ公開中の版を読む。スクリーンショットは
  /// 取り込まない(ストアが返す画像は再圧縮されていて元ファイルと一致しないため)。
  Future<void> pull() async {
    final state = await _load();
    final appInfo = state.selection.appInfoToRead;
    final version = state.selection.versionToRead;
    final appInfoLoc = appInfo == null
        ? null
        : await _appInfoLocalization(appInfo.id);
    final versionLoc = version == null
        ? null
        : await _versionLocalization(version.id);
    stdout.writeln(
      '$_prefix 読み込み元: アプリ情報=${appInfo?.state.raw ?? 'なし'}'
      ' / バージョン=${version == null ? 'なし' : '${version.label} (${version.state.raw})'}',
    );

    final written = _files.writeAscText({
      for (final field in AscTextField.values)
        field: switch (field.scope) {
          AscScope.appInfo => appInfoLoc?.valueOf(field),
          AscScope.version || AscScope.anytime => versionLoc?.valueOf(field),
        },
    });
    for (final path in written) {
      stdout.writeln('$_prefix 書き出しました: $path');
    }
    stdout.writeln(
      '$_prefix スクリーンショットは取り込みません(ストアが返す画像は再圧縮されていて元ファイルと一致しないため)。'
      '管理する場合は元画像を store/asc/$_locale/screenshots/<画面サイズ種別>/ に置いてください',
    );
  }

  /// `store/asc/` の内容をストアへ反映する。[apply] が false なら dry-run。
  Future<void> push({required bool apply}) async {
    final localText = _files.readAscText();
    final localScreenshots = _files.readAscScreenshots();
    throwIfViolations([
      ...checkTextLimits(localText),
      ...checkAscCharacters(localText),
      for (final MapEntry(key: displayType, value: images)
          in localScreenshots.entries)
        ...checkAscScreenshots(displayType, images),
    ]);

    final state = await _load();
    final selection = state.selection;
    stdout.writeln(
      '$_prefix app: ${state.app.name} (${state.app.bundleId})\n'
      '$_prefix 編集中のバージョン: ${switch (selection.editableVersion) {
        final v? => '${v.label} (${v.state.raw})',
        null => 'なし',
      }}',
    );

    // 書き込み先ごとに、その版の現在値と比べる。
    final localizations = <String, AscLocalization>{}; // 書き込み先のid → 言語データ
    Future<AscLocalization> locFor(
      AscWriteTarget target,
    ) async => switch (target) {
      WriteToAppInfo(:final appInfo) =>
        localizations[appInfo.id] ??= await _appInfoLocalization(appInfo.id),
      WriteToVersion(:final version) =>
        localizations[version.id] ??= await _versionLocalization(version.id),
      NotWritable() => throw StateError('unreachable'),
    };

    final patches = <AscLocalization, Map<String, String>>{};
    var changeCount = 0;
    var pendingCount = 0;
    for (final MapEntry(key: field, value: local) in localText.entries) {
      final target = selection.targetFor(field);
      if (target is NotWritable) {
        // 書けない項目は、読める版と比べて差分があるときだけ知らせる。
        final readFrom = switch (field.scope) {
          AscScope.appInfo => selection.appInfoToRead,
          AscScope.version || AscScope.anytime => selection.versionToRead,
        };
        if (readFrom == null) continue;
        final loc = field.scope == AscScope.appInfo
            ? await _appInfoLocalization(readFrom.id)
            : await _versionLocalization(readFrom.id);
        final changes = diffFields(
          local: {field: local},
          remote: {field: loc.valueOf(field)},
        );
        if (changes.single is Changed) {
          pendingCount++;
          stdout.writeln(
            '$_prefix ${field.label}: 変更あり(今は反映できません: ${target.reason})',
          );
        }
        continue;
      }
      final loc = await locFor(target);
      final changes = diffFields(
        local: {field: local},
        remote: {field: loc.valueOf(field)},
      );
      changeCount += printFieldChanges('$_prefix $_locale /', changes);
      if (changes.single case Changed(:final local)) {
        (patches[loc] ??= {})[ascAttributeName(field)] = local;
      }
    }

    // スクリーンショットはバージョン単位。編集中のバージョンにだけ書ける。
    final screenshotPlans = <_ScreenshotPlan>[];
    if (localScreenshots.isNotEmpty) {
      final editable = selection.editableVersion;
      if (editable == null) {
        pendingCount++;
        stdout.writeln('$_prefix スクリーンショット: 編集中のバージョンが無いため今は比較・反映しません');
      } else {
        final versionLoc = await locFor(WriteToVersion(editable));
        final sets = [
          for (final r in await _client.getAll(
            'appStoreVersionLocalizations/${versionLoc.id}/appScreenshotSets',
          ))
            AscScreenshotSet.fromResource(r),
        ];
        for (final MapEntry(key: displayType, value: images)
            in localScreenshots.entries) {
          final set = sets
              .where((s) => s.displayType == displayType)
              .firstOrNull;
          final remote = set == null
              ? <AscScreenshot>[]
              : [
                  for (final r in await _client.getAll(
                    'appScreenshotSets/${set.id}/appScreenshots',
                  ))
                    AscScreenshot.fromResource(r),
                ];
          final same = sameImageSequence(
            [for (final image in images) md5.convert(image.bytes).toString()],
            [for (final s in remote) s.sourceFileChecksum],
          );
          if (same) {
            stdout.writeln('$_prefix スクリーンショット $displayType: 変更なし');
          } else {
            changeCount++;
            stdout.writeln(
              '$_prefix スクリーンショット $displayType: 変更あり'
              '(ストア${remote.length}枚 → ファイル${images.length}枚。全枚を差し替えます)',
            );
            screenshotPlans.add(
              _ScreenshotPlan(
                displayType: displayType,
                versionLocalizationId: versionLoc.id,
                existingSetId: set?.id,
                remote: remote,
                images: images,
              ),
            );
          }
        }
      }
    }

    if (!apply || changeCount == 0) {
      printDryRunFooter(changeCount);
      if (pendingCount > 0) {
        stdout.writeln('今は反映できない変更が$pendingCount件あります(上の表示を参照)');
      }
      return;
    }

    for (final MapEntry(key: loc, value: attributes) in patches.entries) {
      await _client.patch('${loc.type}/${loc.id}', {
        'data': {'type': loc.type, 'id': loc.id, 'attributes': attributes},
      });
      stdout.writeln('$_prefix 更新しました: ${attributes.keys.join(', ')}');
    }
    for (final plan in screenshotPlans) {
      await _replaceScreenshots(plan);
      stdout.writeln(
        '$_prefix スクリーンショット ${plan.displayType}: ${plan.images.length}枚を差し替えました',
      );
    }
  }

  /// [ipa] を App Store Connect へアップロードする(使う側のリリーススクリプトから呼ぶ)。
  /// 処理が終わると TestFlight に出る(数分〜数十分。待たずに戻る)。
  ///
  /// dry-run ではアップロードせず、[buildNumber] がこのアプリにある最大のビルド番号
  /// より大きいことだけを確かめる(ビルドの前に呼ぶため、dry-run では [ipa] が無くてよい)。
  /// アップロードは `xcrun altool` が行う(ASC API にアップロードの手段が無いため)。
  Future<void> upload({
    required File ipa,
    required String versionName,
    required int buildNumber,
    required bool apply,
  }) async {
    if (apply && !ipa.existsSync()) {
      throw CliException('IPAがありません: ${ipa.path}');
    }
    final app = await _findApp();
    final existing = [
      for (final r in await _client.getAll('builds', {'filter[app]': app.id}))
        ?int.tryParse(AscBuild.fromResource(r).version ?? ''),
    ];
    final problem = checkNewBuildNumber(existing, buildNumber);
    if (problem != null) throw CliException(problem);
    stdout.writeln('$_prefix ビルド番号 $buildNumber はまだ使われていません');

    if (!apply) {
      stdout.writeln('dry-run: アップロードするには --apply を付けてください');
      return;
    }

    // altool は鍵をファイルでしか受け取れない(--auth-string は引数に秘密が載るので使わない)。
    // 本人だけが読める一時ディレクトリに置き、終わったら必ず消す。
    final keyDir = Directory.systemTemp.createTempSync('asc-key-');
    try {
      await Process.run('chmod', ['700', keyDir.path]);
      final p8 = File('${keyDir.path}/AuthKey_${_credentials.keyId}.p8')
        ..createSync();
      await Process.run('chmod', ['600', p8.path]);
      p8.writeAsStringSync(_credentials.privateKeyPem);

      stdout.writeln('$_prefix アップロードしています: ${ipa.path}');
      final process = await Process.start(
        'xcrun',
        altoolUploadArgs(
          ipaPath: ipa.path,
          appleId: app.id,
          bundleId: ascBundleId,
          versionName: versionName,
          buildNumber: '$buildNumber',
          keyId: _credentials.keyId,
          issuerId: _credentials.issuerId,
          p8Path: p8.path,
        ),
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await process.exitCode;
      if (code != 0) {
        throw CliException('altool のアップロードが失敗しました(終了コード $code)');
      }
    } finally {
      keyDir.deleteSync(recursive: true);
    }
    stdout.writeln(
      '$_prefix アップロードしました: $versionName ($buildNumber)。'
      'TestFlight に出るまで数分〜数十分かかります',
    );
  }

  /// TestFlight にあるビルドを選んで審査へ出す。
  Future<void> submit({
    required String versionName,
    required String buildNumber,
    required bool apply,
  }) async {
    final notes = _files.readReleaseNotes(versionName);

    final state = await _load();
    final existing = state.versions
        .where((v) => v.versionString == versionName)
        .firstOrNull;
    if (existing != null && !existing.state.editable) {
      throw CliException(
        'バージョン $versionName は審査に出せる状態ではありません(${existing.state.raw})',
      );
    }
    final otherEditable = state.selection.editableVersion;
    if (existing == null &&
        otherEditable != null &&
        otherEditable.label != versionName) {
      throw CliException(
        '編集中のバージョン ${otherEditable.label} があります。'
        'App Store Connect で $versionName に名前を変えるか、そちらを指定してください',
      );
    }

    final builds = [
      for (final r in await _client.getAll('builds', {
        'filter[app]': state.app.id,
        'filter[version]': buildNumber,
        'filter[preReleaseVersion.version]': versionName,
      }))
        AscBuild.fromResource(r),
    ];
    final build = builds.firstOrNull;
    if (build == null) {
      throw CliException(
        'TestFlight にビルド $versionName ($buildNumber) がありません。先にアップロードしてください',
      );
    }
    if (build.processingState != 'VALID') {
      throw CliException(
        'ビルド $versionName ($buildNumber) はまだ使えません(processingState=${build.processingState})',
      );
    }

    // 初めて公開する版には「このバージョンの新機能」を書けない(ASCが拒否する)。
    final isFirstRelease = !state.versions.any(
      (v) => v.state.live || v.state == AscState.replacedWithNewVersion,
    );
    // リリースノートの検査は送るときだけ。初回公開は送らないので、Playが
    // 受け付けた「→」入りの文面のままでも止めない(2026-11-06に1.0で踏んだ)。
    if (!isFirstRelease) {
      throwIfViolations([
        ?checkReleaseNotes(
          notes,
          label: 'リリースノート($versionName)',
          max: ascReleaseNotesMax,
        ),
        for (final character in ascRejectedCharacters)
          if (notes.contains(character))
            RejectedCharacter(
              label: 'リリースノート($versionName)',
              character: character,
            ),
      ]);
    }

    stdout
      ..writeln('$_prefix app: ${state.app.name} (${state.app.bundleId})')
      ..writeln(
        '$_prefix バージョン $versionName: '
        '${existing == null ? '新しく作成します' : '既存(${existing.state.raw})'}',
      )
      ..writeln('$_prefix ビルド: $buildNumber')
      ..writeln('$_prefix リリース方法: 審査通過後に手動で公開(MANUAL)');
    if (isFirstRelease) {
      stdout.writeln('$_prefix 初回の公開のため、リリースノート(このバージョンの新機能)は付けません');
    } else {
      stdout
        ..writeln('$_prefix リリースノート:')
        ..writeln(notes.split('\n').map((l) => '    $l').join('\n'));
    }
    stdout.writeln('$_prefix 掲載情報の変更は先に `asc push --apply` で反映しておいてください');

    if (!apply) {
      stdout.writeln('dry-run: 審査へ出すには --apply を付けてください');
      return;
    }

    final versionId =
        existing?.id ??
        (await _client.post('appStoreVersions', {
          'data': {
            'type': 'appStoreVersions',
            'attributes': {
              'platform': 'IOS',
              'versionString': versionName,
              'releaseType': 'MANUAL',
            },
            'relationships': {'app': ascRef('apps', state.app.id)},
          },
        })).id;
    if (existing != null) {
      await _client.patch('appStoreVersions/$versionId', {
        'data': {
          'type': 'appStoreVersions',
          'id': versionId,
          'attributes': {'releaseType': 'MANUAL'},
        },
      });
    }
    await _client.patch(
      'appStoreVersions/$versionId/relationships/build',
      ascRef('builds', build.id),
    );
    stdout.writeln('$_prefix ビルドを紐付けました');

    if (!isFirstRelease) {
      final loc = await _versionLocalization(versionId);
      await _client.patch('appStoreVersionLocalizations/${loc.id}', {
        'data': {
          'type': 'appStoreVersionLocalizations',
          'id': loc.id,
          'attributes': {'whatsNew': notes},
        },
      });
      stdout.writeln('$_prefix リリースノートを書きました');
    }

    // まだ送っていない提出物があれば使い回す(1アプリにつき1つしか作れない)。
    final open = [
      for (final r in await _client.getAll('reviewSubmissions', {
        'filter[app]': state.app.id,
        'filter[platform]': 'IOS',
        'filter[state]': 'READY_FOR_REVIEW',
      }))
        AscReviewSubmission.fromResource(r),
    ].firstOrNull;
    final submissionId =
        open?.id ??
        (await _client.post('reviewSubmissions', {
          'data': {
            'type': 'reviewSubmissions',
            'attributes': {'platform': 'IOS'},
            'relationships': {'app': ascRef('apps', state.app.id)},
          },
        })).id;
    await _client.post('reviewSubmissionItems', {
      'data': {
        'type': 'reviewSubmissionItems',
        'relationships': {
          'reviewSubmission': ascRef('reviewSubmissions', submissionId),
          'appStoreVersion': ascRef('appStoreVersions', versionId),
        },
      },
    });
    await _client.patch('reviewSubmissions/$submissionId', {
      'data': {
        'type': 'reviewSubmissions',
        'id': submissionId,
        'attributes': {'submitted': true},
      },
    });
    stdout.writeln('$_prefix 審査へ送りました。通過後の公開は App Store Connect で手動で行ってください');
  }

  // ---- 読み込み ----

  Future<AscApp> _findApp() async {
    final apps = await _client.getAll('apps', {
      'filter[bundleId]': ascBundleId,
    });
    final app = apps
        .map(AscApp.fromResource)
        .where((a) => a.bundleId == ascBundleId) // 念のため完全一致で確かめる
        .firstOrNull;
    if (app == null) {
      throw CliException('App Store Connect に $ascBundleId のアプリがありません');
    }
    return app;
  }

  Future<_AppState> _load() async {
    final app = await _findApp();
    final appInfos = [
      for (final r in await _client.getAll('apps/${app.id}/appInfos'))
        AscAppInfo.fromResource(r),
    ];
    final versions =
        [
          for (final r in await _client.getAll(
            'apps/${app.id}/appStoreVersions',
            {'filter[platform]': 'IOS'},
          ))
            AscVersion.fromResource(r),
        ]..sort(
          (a, b) => (b.createdDate ?? DateTime(0)).compareTo(
            a.createdDate ?? DateTime(0),
          ),
        );
    return _AppState(app: app, appInfos: appInfos, versions: versions);
  }

  Future<AscLocalization> _appInfoLocalization(String appInfoId) =>
      _localization('appInfos/$appInfoId/appInfoLocalizations');

  Future<AscLocalization> _versionLocalization(String versionId) =>
      _localization('appStoreVersions/$versionId/appStoreVersionLocalizations');

  Future<AscLocalization> _localization(String path) async {
    final locs = [
      for (final r in await _client.getAll(path))
        AscLocalization.fromResource(r),
    ];
    final loc = locs.where((l) => l.locale == _locale).firstOrNull;
    if (loc == null) {
      throw CliException(
        '$_locale の言語データがありません($path)。'
        'App Store Connect で日本語を追加してください',
      );
    }
    return loc;
  }

  // ---- スクリーンショット ----

  /// 既存のスクリーンショットを消し、ファイルの並びどおりに上げ直す。
  ///
  /// 1枚ごとに「予約 → 実体の送信 → MD5付きで確定」の3段。最後に並び順を明示する。
  Future<void> _replaceScreenshots(_ScreenshotPlan plan) async {
    final setId =
        plan.existingSetId ??
        (await _client.post('appScreenshotSets', {
          'data': {
            'type': 'appScreenshotSets',
            'attributes': {'screenshotDisplayType': plan.displayType},
            'relationships': {
              'appStoreVersionLocalization': ascRef(
                'appStoreVersionLocalizations',
                plan.versionLocalizationId,
              ),
            },
          },
        })).id;
    for (final old in plan.remote) {
      await _client.delete('appScreenshots/${old.id}');
    }
    final ids = <String>[];
    for (final image in plan.images) {
      final reserved = AscScreenshot.fromResource(
        await _client.post('appScreenshots', {
          'data': {
            'type': 'appScreenshots',
            'attributes': {
              'fileName': image.fileName,
              'fileSize': image.bytes.length,
            },
            'relationships': {
              'appScreenshotSet': ascRef('appScreenshotSets', setId),
            },
          },
        }),
      );
      for (final op in reserved.uploadOperations) {
        await _client.upload(op, image.bytes);
      }
      await _client.patch('appScreenshots/${reserved.id}', {
        'data': {
          'type': 'appScreenshots',
          'id': reserved.id,
          'attributes': {
            'uploaded': true,
            'sourceFileChecksum': md5.convert(image.bytes).toString(),
          },
        },
      });
      ids.add(reserved.id);
    }
    await _client.patch(
      'appScreenshotSets/$setId/relationships/appScreenshots',
      {
        'data': [
          for (final id in ids) {'type': 'appScreenshots', 'id': id},
        ],
      },
    );
  }
}

final class _ScreenshotPlan {
  _ScreenshotPlan({
    required this.displayType,
    required this.versionLocalizationId,
    required this.existingSetId,
    required this.remote,
    required this.images,
  });

  final String displayType;
  final String versionLocalizationId;
  final String? existingSetId;
  final List<AscScreenshot> remote;
  final List<LocalImage> images;
}
