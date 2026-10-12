# Claru AIの操作定義

このディレクトリには、Claru AIの画面判定条件、操作対象、状態遷移を記述したJSONの操作定義例を置きます。共通の`field-app`実行器が定義を読み込み、タスク選択、録画開始、録画終了後の処理、次チャンクの開始を進めます。

[`course.example.json`](course.example.json)を`config/local/`へコピーし、現在インストールされているClaru AIのアクセシビリティ識別子へ置き換えます。

```sh
mkdir -p config/local
cp apps/claru-app/course.example.json config/local/claru.json
```

現在の操作定義例は完了画面で`discard-recording`を実行します。Claruの録画や送信への影響を確認するまでは、実タスクで開始しないでください。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/claru.json
```

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_DEVICE_LABEL=claru-01 \
FAO_WDA_LOCAL_PORT=8200 \
swift run --package-path mac/controller-core field-app \
  --course config/local/claru.json
```

Claru AIのApp Store識別子は`6771087735`、iOS bundle identifierは`ai.claru.app`です。公開ストア情報は[Claru AI - App Store](https://apps.apple.com/us/app/claru-ai/id6771087735)で確認できます。
