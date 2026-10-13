# Minute Dataの操作定義

Minute Dataを操作するための操作定義です。画面の目印とボタンは、Minute 1.29.0で確かめた値です。

撮るタスクは端末ごとに決めます。例をコピーし、`REPLACE_WITH_TASK_TITLE`を、タスク一覧に出ているタスク名に置き換えます。次の例ではFood Prepにしています。

```sh
mkdir -p config/local
sed 's/REPLACE_WITH_TASK_TITLE/Food Prep/g' apps/minute-app/definition.example.json > config/local/minute.json
swift run --package-path mac/controller-core field-app \
  --validate-definition config/local/minute.json
```

例の`afterRecording`は`discard`で、録画が終わるたびに破棄します。保存するときは`save`に変えます。止めたときは、カメラを切ったタスクの説明カードで待ちます。

設定の中の画面や開いたままのシートのように、操作定義にない画面にいるときは、Minuteを起動し直してタスク一覧から進めます。録画の画面（`record-screen`がある画面）では起動し直さず、人を待ちます。起動し直すと撮りかけの録画が失われ、完了画面で保存か破棄を待っている録画も失われるおそれがあるためです。

起動するときは、端末ごとに`FAO_DEVICE_ID`、`FAO_DEVICE_LABEL`、`FAO_CONTROL_PORT`を変えます。`FAO_CONTROL_PORT`と`FAO_CONTROL_TOKEN`は、背面タップで止める・再開するときに使います。`caffeinate -i`は、動いている間Macをスリープさせません。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVICE_LABEL=minute-01 \
FAO_CONTROL_PORT=8400 \
FAO_CONTROL_TOKEN=<16文字以上のトークン> \
caffeinate -i swift run --package-path mac/controller-core field-app \
  --definition config/local/minute.json
```
