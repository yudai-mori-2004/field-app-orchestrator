# Minute Data course

このディレクトリは、共通の`field-app`実行器にMinute Dataの画面と操作経路を教えるコースです。端末制御、開始・一時停止、Appium接続、切断処理を独自実装しません。

[`course.example.json`](course.example.json)を`config/local/`へコピーし、現在インストールされているMinute Dataのアクセシビリティ識別子へ置き換えます。

```sh
mkdir -p config/local
cp apps/minute-app/course.example.json config/local/minute.json
```

`open-task`には、一覧の先頭ではなく、その端末へ割り当てたタスクを一意に示すidentifierを設定します。画面証明や操作対象が0件または複数件なら、共通実行器はタップせず停止します。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/minute.json
```

現在のコースは、録画完了後に`discard-recording`を実行します。Minute Dataは完了前からアップロードする可能性があるため、discardは「サーバーへ一度も送信されない」ことを保証しません。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_DEVICE_LABEL=minute-01 \
FAO_WDA_LOCAL_PORT=8100 \
swift run --package-path mac/controller-core field-app \
  --course config/local/minute.json
```
