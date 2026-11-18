# store_cli

Google Play と App Store Connect の掲載情報・リリースノート・審査提出を、リポジトリの `store/` にあるファイルから管理するCLI。
fastlane の代わりに、使う機能だけを Dart で書いたもの。

- **既定は dry-run**(差分と検査結果を表示するだけ)。`--apply` を付けたときだけ書き込む
- 字数・画像の検査は API を叩く前に行い、違反があれば何も送らずに止まる
- コードにアプリ固有の値は無い。パッケージ名・バンドルID・サービスアカウント・言語は、使う側の `store/store.yaml` から読む
- **CI からは反映しない**。ストアへ書き込むコマンドは利用者のターミナルで実行する

## インストール

使う側のリポジトリの `mise.toml` で版を固定する(macOS arm64 のみ)。

```toml
[tools]
"github:levain-labs/store_cli" = "1.0.0"
```

`mise install` のあと `store --help` で使える。

## 使う側に置くもの

```
store/
├─ store.yaml                      # アプリ固有の値(下記)。CLI が store/ を見つける目印でもある
├─ .env.store                      # App Store Connect の鍵の 1Password 参照(op://…)だけ
├─ play/<language>/
│  ├─ title.txt                    # アプリ名(30字)
│  ├─ short_description.txt        # 簡単な説明(80字)
│  ├─ full_description.txt         # 詳しい説明(4000字)
│  └─ images/
│     ├─ icon.png                  # 512×512
│     ├─ featureGraphic.png        # 1024×500
│     └─ phoneScreenshots/01.png … # ファイル名順に並ぶ(8枚まで)
├─ asc/<locale>/
│  ├─ name.txt                     # 名前(30字)            ┐アプリ単位
│  ├─ subtitle.txt                 # サブタイトル(30字)     │
│  ├─ privacy_url.txt              # プライバシーポリシーURL ┘
│  ├─ description.txt              # 説明(4000字)          ┐バージョン単位
│  ├─ keywords.txt                 # キーワード(カンマ区切り100字)
│  ├─ support_url.txt / marketing_url.txt                  ┘
│  ├─ promotional_text.txt         # プロモーションテキスト(170字。いつでも変えられる)
│  └─ screenshots/APP_IPHONE_67/01.png …  # ディレクトリ名=ASCの画面サイズ種別(10枚まで)
└─ release-notes/<バージョン名>.txt # 例 1.0.1.txt。両ストア共通(Playの上限500字に合わせる)
```

```yaml
# store/store.yaml
play:
  package_name: com.example.app          # applicationId
  language: ja-JP                        # store/play/<language>/ のディレクトリ名
  service_account: play-publisher@<project>.iam.gserviceaccount.com  # なりすます相手
asc:
  bundle_id: com.example.app
  locale: ja                             # store/asc/<locale>/ のディレクトリ名
```

```sh
# store/.env.store
ASC_KEY_ID="op://<vault>/<item>/key id"
ASC_ISSUER_ID="op://<vault>/<item>/issuer id"
ASC_PRIVATE_KEY="op://<vault>/<item>/key.p8"
```

- `store/` はカレントディレクトリから上へたどって `store/store.yaml` を探す。別の場所なら `--store-dir`
- 知らないキーや抜けは起動時に止まる(書き間違いが既定値に落ちない)
- 1ファイル1項目のプレーンテキスト。末尾の改行は無視される
- **ファイルが無い項目は管理しない**(ストアの値に触らない)。値を空にしたいときは空のファイルを置く

## 使い方

```sh
# 最初の1回: ストアの現状を取り込む
store play pull
op run --env-file=store/.env.store -- store asc pull

# 掲載情報を直して反映する
store play push                  # dry-run。Play側の検査(edits.validate)まで通す
store play push --apply
op run --env-file=store/.env.store -- store asc push
op run --env-file=store/.env.store -- store asc push --apply

# ビルドを上げる(リリーススクリプトから呼ぶ想定)
store play upload --aab app-release.aab --version 1.0.1 --version-code 12 --apply   # 内部テストへ
op run --env-file=store/.env.store -- store asc upload --ipa app.ipa --version 1.0.1 --build 12 --apply

# 審査に出す
store play submit --version 1.0.1 --version-code 12 --apply          # 本番トラックへ下書き
store play submit --version 1.0.1 --version-code 12 --apply --send   # 審査へ送る
op run --env-file=store/.env.store -- store asc submit --version 1.0.1 --build 12 --apply
```

審査通過後の公開は両ストアとも手動。

## 認証の準備(アプリごとではなく開発者アカウントごとに1回)

- **App Store Connect**: 「ユーザとアクセス」→「統合」→「App Store Connect API」でチームキー(アクセス: App Manager)を発行し、Key ID・Issuer ID と `AuthKey_<KeyID>.p8` を 1Password の1項目に保存する。チームキーなので同じチームの全アプリで使える
- **Google Play**: 鍵ファイルは使わない。サービスアカウントを作り(JSONキーは発行しない)、自分に `roles/iam.serviceAccountTokenCreator` を付け、Play Console の「ユーザーと権限」に招待する。以後は `gcloud auth login` 済みなら、CLI が `gcloud auth print-access-token --impersonate-service-account=…` でトークンを得る

## 地雷

1. `pull` は画像を取り込まない。ストアが返す画像は再圧縮されていて元ファイルと一致しないため。画像は PNG の元ファイルを `store/` に置く
2. App Store Connect のバージョン単位の項目とスクリーンショットは、**審査に出していないバージョン**があるときしか書けない(プロモーションテキストを除く)。無いときは dry-run が「今は反映できません」と知らせる
3. 初めて公開するバージョンには App Store Connect がリリースノートを受け付けないので、`asc submit` は自動で付けない
4. 本番公開前のアプリでは、サービスアカウントに Play Console の「Edit and delete draft apps」が無いと、`pull` は通るのに掲載情報の書き込みだけが 403 になる
5. App Store Connect は文字によって 409 で拒否する(プロモーションテキストの「→」で確認)。見つけたら `lib/domain/limits.dart` の `ascRejectedCharacters` に足す
6. Google Play はアルファ付きの PNG を受け付けない(CLI の検査が弾く)

## 開発

```sh
mise install
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart run bin/store.dart --help   # ビルドせずに動かす
```

- 判断は `lib/domain/` の純関数に置き、`test/domain/` で固定する。HTTP・ファイル・プロセスは薄い境界(`lib/play/`・`lib/asc/`・`lib/store_files.dart`)に閉じる
- 依存は完全固定(キャレットを使わない)

## リリース

1. `pubspec.yaml` の `version` を上げるコミットを main に入れる
2. `git tag v<version> && git push origin v<version>`
3. `release.yaml` が macOS arm64 の実行ファイルを作って GitHub Release に添付する
4. 使う側の `mise.toml` の版を上げる

## ライセンス

MIT
