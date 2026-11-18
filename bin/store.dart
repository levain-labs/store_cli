// エントリポイント。引数を解釈してコマンドへ振り分けるだけで、ロジックは書かない。
//
//   store play pull | push [--apply] | submit --version 1.0.1 --version-code 12 [--apply [--send]]
//              | upload --aab app-release.aab --version 1.0.1 --version-code 12 [--apply]
//   store asc  pull | push [--apply] | submit --version 1.0.1 --build 12 [--apply]
//              | upload --ipa app.ipa --version 1.0.1 --build 12 [--apply]
//
// 正本は使う側のリポジトリ直下の store/(アプリ固有の値は store/store.yaml)。
// 使い方は README.md。
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:googleapis/androidpublisher/v3.dart';

import 'package:store_cli/asc/asc_client.dart';
import 'package:store_cli/asc/asc_commands.dart';
import 'package:store_cli/asc/asc_jwt.dart';
import 'package:store_cli/cli_exception.dart';
import 'package:store_cli/play/play_auth.dart';
import 'package:store_cli/play/play_commands.dart';
import 'package:store_cli/store_files.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>('store', 'ストアの掲載情報・リリースノート・審査提出を store/ のファイルから管理する')
        ..argParser.addOption(
          'store-dir',
          help: 'store/ の場所(省略時はリポジトリ直下の store/)',
        )
        ..addCommand(_PlayCommand())
        ..addCommand(_AscCommand());
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on CliException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on AscApiException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on PlayApiException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}

/// 必須の値を読む。認証(gcloud・鍵)より前に確かめ、使い方の誤りとして止める
/// (args の `mandatory: true` は値を読むまで検査されず、認証のあとに落ちるため使わない)。
String _required(Command<void> command, String name) {
  final value = command.argResults!.option(name);
  if (value == null || value.isEmpty) {
    command.usageException('--$name を指定してください');
  }
  return value;
}

StoreFiles _files(Command<void> command) =>
    StoreFiles.locate(storeDir: command.globalResults?['store-dir'] as String?);

// ---- play ----

final class _PlayCommand extends Command<void> {
  _PlayCommand() {
    argParser.addOption(
      'service-account',
      help: 'なりすますサービスアカウント(省略時は store.yaml の play.service_account)',
    );
    addSubcommand(_PlayPull());
    addSubcommand(_PlayPush());
    addSubcommand(_PlaySubmit());
    addSubcommand(_PlayUpload());
  }

  @override
  String get name => 'play';
  @override
  String get description => 'Google Play(gcloud のなりすましで認証。鍵ファイル不要)';
}

/// play 配下のサブコマンドの共通部分。引数を先に解釈し([bind])、
/// 誤りがあれば gcloud を呼ぶ前に止める。そのあと認証してコマンドを実行する。
abstract base class _PlaySub extends Command<void> {
  Future<void> Function(PlayCommands commands) bind();

  @override
  Future<void> run() async {
    final runWith = bind();
    final files = _files(this);
    final token = await fetchPlayAccessToken(
      serviceAccount:
          parent!.argResults!.option('service-account') ??
          files.config.play.serviceAccount,
    );
    final client = BearerClient(token);
    try {
      await runWith(PlayCommands(AndroidPublisherApi(client), files));
    } finally {
      client.close();
    }
  }
}

final class _PlayPull extends _PlaySub {
  @override
  String get name => 'pull';
  @override
  String get description => 'ストアの掲載情報(テキスト)を store/play/ へ書き出す';
  @override
  Future<void> Function(PlayCommands) bind() =>
      (commands) => commands.pull();
}

final class _PlayPush extends _PlaySub {
  _PlayPush() {
    argParser.addFlag('apply', negatable: false, help: '実際に反映する(省略時は dry-run)');
  }

  @override
  String get name => 'push';
  @override
  String get description => 'store/play/ の掲載情報・画像をストアへ反映する';
  @override
  Future<void> Function(PlayCommands) bind() {
    final apply = argResults!.flag('apply');
    return (commands) => commands.push(apply: apply);
  }
}

final class _PlaySubmit extends _PlaySub {
  _PlaySubmit() {
    argParser
      ..addOption('version', help: '(必須)バージョン名(例 1.0.1)。リリースノートのファイル名になる')
      ..addOption('version-code', help: '(必須)内部テストにある versionCode')
      ..addFlag('apply', negatable: false, help: '実際に反映する(省略時は dry-run)')
      ..addFlag('send', negatable: false, help: '下書きではなく審査へ送る(--apply と併用)');
  }

  @override
  String get name => 'submit';
  @override
  String get description => '内部テストのビルドを本番トラックへ(既定は下書き)';
  @override
  Future<void> Function(PlayCommands) bind() {
    final versionName = _required(this, 'version');
    final code = int.tryParse(_required(this, 'version-code'));
    if (code == null) usageException('--version-code は整数で指定してください');
    final apply = argResults!.flag('apply');
    final send = argResults!.flag('send');
    if (send && !apply) usageException('--send は --apply と一緒に指定してください');
    return (commands) => commands.submit(
      versionName: versionName,
      versionCode: code,
      apply: apply,
      send: send,
    );
  }
}

final class _PlayUpload extends _PlaySub {
  _PlayUpload() {
    argParser
      ..addOption('aab', help: '(--apply のとき必須)アップロードするAAB')
      ..addOption('version', help: '(必須)バージョン名(例 1.0.1)。内部テストのリリース名になる')
      ..addOption('version-code', help: '(必須)AABの versionCode(build number)')
      ..addFlag('apply', negatable: false, help: '実際にアップロードする(省略時は番号の確認だけ)');
  }

  @override
  String get name => 'upload';
  @override
  String get description => 'AABを内部テストのトラックへ出す';
  @override
  Future<void> Function(PlayCommands) bind() {
    final versionName = _required(this, 'version');
    final code = int.tryParse(_required(this, 'version-code'));
    if (code == null) usageException('--version-code は整数で指定してください');
    final apply = argResults!.flag('apply');
    final aab = argResults!.option('aab');
    if (apply && (aab == null || aab.isEmpty)) {
      usageException('--apply のときは --aab を指定してください');
    }
    return (commands) => commands.upload(
      aab: File(aab ?? ''),
      versionName: versionName,
      versionCode: code,
      apply: apply,
    );
  }
}

// ---- asc ----

final class _AscCommand extends Command<void> {
  _AscCommand() {
    addSubcommand(_AscPull());
    addSubcommand(_AscPush());
    addSubcommand(_AscSubmit());
    addSubcommand(_AscUpload());
  }

  @override
  String get name => 'asc';
  @override
  String get description =>
      'App Store Connect(op run --env-file=store/.env.store -- で鍵を渡す)';
}

abstract base class _AscSub extends Command<void> {
  Future<void> Function(AscCommands commands) bind();

  @override
  Future<void> run() async {
    final runWith = bind();
    final files = _files(this);
    final credentials = AscCredentials.fromEnvironment(Platform.environment);
    final client = AscClient(credentials);
    try {
      await runWith(AscCommands(client, files, credentials));
    } finally {
      client.close();
    }
  }
}

final class _AscPull extends _AscSub {
  @override
  String get name => 'pull';
  @override
  String get description => 'ストアの掲載情報(テキスト)を store/asc/ へ書き出す';
  @override
  Future<void> Function(AscCommands) bind() =>
      (commands) => commands.pull();
}

final class _AscPush extends _AscSub {
  _AscPush() {
    argParser.addFlag('apply', negatable: false, help: '実際に反映する(省略時は dry-run)');
  }

  @override
  String get name => 'push';
  @override
  String get description => 'store/asc/ の掲載情報・スクリーンショットをストアへ反映する';
  @override
  Future<void> Function(AscCommands) bind() {
    final apply = argResults!.flag('apply');
    return (commands) => commands.push(apply: apply);
  }
}

final class _AscSubmit extends _AscSub {
  _AscSubmit() {
    argParser
      ..addOption('version', help: '(必須)バージョン名(例 1.0.1)')
      ..addOption('build', help: '(必須)TestFlight にあるビルド番号')
      ..addFlag('apply', negatable: false, help: '実際に審査へ出す(省略時は dry-run)');
  }

  @override
  String get name => 'submit';
  @override
  String get description => 'TestFlight のビルドを選んで審査へ出す';
  @override
  Future<void> Function(AscCommands) bind() {
    final versionName = _required(this, 'version');
    final buildNumber = _required(this, 'build');
    final apply = argResults!.flag('apply');
    return (commands) => commands.submit(
      versionName: versionName,
      buildNumber: buildNumber,
      apply: apply,
    );
  }
}

final class _AscUpload extends _AscSub {
  _AscUpload() {
    argParser
      ..addOption('ipa', help: '(--apply のとき必須)アップロードするIPA')
      ..addOption(
        'version',
        help: '(必須)バージョン名(CFBundleShortVersionString。例 1.0.1)',
      )
      ..addOption('build', help: '(必須)ビルド番号(CFBundleVersion)')
      ..addFlag('apply', negatable: false, help: '実際にアップロードする(省略時は番号の確認だけ)');
  }

  @override
  String get name => 'upload';
  @override
  String get description =>
      'IPAを App Store Connect へアップロードする(処理が終わると TestFlight に出る)';
  @override
  Future<void> Function(AscCommands) bind() {
    final versionName = _required(this, 'version');
    final buildNumber = int.tryParse(_required(this, 'build'));
    if (buildNumber == null) usageException('--build は整数で指定してください');
    final apply = argResults!.flag('apply');
    final ipa = argResults!.option('ipa');
    if (apply && (ipa == null || ipa.isEmpty)) {
      usageException('--apply のときは --ipa を指定してください');
    }
    return (commands) => commands.upload(
      ipa: File(ipa ?? ''),
      versionName: versionName,
      buildNumber: buildNumber,
      apply: apply,
    );
  }
}
