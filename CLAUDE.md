# store_cli

ストアの掲載情報・リリースノート・審査提出を、使う側のリポジトリの `store/` から管理するCLI(純Dart)。使い方・地雷・リリース手順は `README.md`。

## 守ること

- **コードにアプリ固有の値を書かない**。パッケージ名・バンドルID・サービスアカウント・言語は `store/store.yaml` から読む(`lib/domain/store_config.dart`)。知らないキーや抜けは起動時に止める
- **既定は dry-run**。書き込みは `--apply` のときだけ。字数・画像の検査は API を叩く前に行う
- **CI からストアへ反映しない**。CI は整形・`dart analyze --fatal-infos`・`dart test` のみ。ストアの API を叩くコマンドは利用者のターミナルで実行してもらう(ASC は `op run` で 1Password の鍵を渡すため。Play は gcloud のなりすまし)
- 判断は `lib/domain/` の純関数に置き、`test/domain/` で固定する。HTTP・ファイル・プロセスは薄い境界に留める
- 継承しないクラスは `final class`、結果の分岐は `sealed class`。catch は `on X catch (error, stackTrace)`
- 相対 import は使わない。依存は完全固定(キャレットを使わない)
- 時刻は `DateTime Function() now` を引数で受ける
- コメント・メッセージ・ドキュメントは日本語

## リリース

`pubspec.yaml` の `version` とタグ `v<version>` を一致させる(`release.yaml` が照合する)。使う側は `mise.toml` で版を固定しているので、使う側の変更が要る修正は README の「地雷」にも書く。
