# Minute Dataの操作定義

Minute Dataを操作するための操作定義の例です。

[`course.example.json`](course.example.json)を`config/local/`へコピーし、`REPLACE_WITH_`で始まる値を、インストールされているMinute Dataで調べたアクセシビリティ識別子に置き換えます。`open-task`には、一覧の先頭ではなく、そのiPhoneで撮るタスクを一つだけ示す識別子を入れます。

```sh
mkdir -p config/local
cp apps/minute-app/course.example.json config/local/minute.json
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/minute.json
```

定義例は、録画が終わると録画を破棄し、次の録画を始めます。完了後の画面で押すボタンは、操作定義で変えられます。

起動するときは、端末ごとに`FAO_DEVICE_LABEL`と`FAO_WDA_LOCAL_PORT`を変えます。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_DEVICE_LABEL=minute-01 \
FAO_WDA_LOCAL_PORT=8100 \
swift run --package-path mac/controller-core field-app \
  --course config/local/minute.json
```
