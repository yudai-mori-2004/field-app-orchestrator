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

起動するときは、端末ごとに`FAO_DEVICE_LABEL`と`FAO_WDA_LOCAL_PORT`を変えます。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_DEVICE_LABEL=minute-01 \
FAO_WDA_LOCAL_PORT=8100 \
swift run --package-path mac/controller-core field-app \
  --definition config/local/minute.json
```
