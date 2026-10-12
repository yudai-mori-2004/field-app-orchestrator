# Minute app

`minute-app`は、Minute Dataを一台のiPhoneで継続運転するための本番アダプターとCLIです。共通のDevice Workerへ、Minute固有の画面判定、タスク選択、録画開始・停止、完了時の処理だけを提供します。

現在の完了ポリシーは次の二つです。

- `discardAfterEachChunk`: 完了画面でdiscardを押し、目標状態が`running`なら次のチャンクを始めます。
- `requireOperator`: 完了画面で操作せず、その端末だけを`needsAttention`にします。

提出を確定する操作はまだ実装していません。Minute Dataは録画中または完了前からアップロードする可能性があるため、`discardAfterEachChunk`も「サーバーへ一度も送信されない」ことを保証しません。

## ローカル設定

対象タスクと各画面のアクセシビリティ識別子は、インストール中のMinute Dataで確認した値を使います。例をコピーし、Gitから除外される`config/local/`へ保存してください。

```sh
mkdir -p config/local
cp apps/minute-app/config/minute-app.example.json config/local/minute-app.json
```

プレースホルダーを残したまま実行しないでください。ホーム画面の`taskCard`には、先頭カードを意味するprefixではなく、その端末へ割り当てたタスクを一意に示すidentifierを指定します。要素が0件または複数件なら操作を止めます。

## 一台での起動

先にリポジトリ直下でAppiumを起動します。

```sh
npm run appium
```

別のターミナルで、端末と署名情報を実行時だけ渡します。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_WDA_LOCAL_PORT=8100 \
swift run --package-path apps/minute-app minute-app \
  --config config/local/minute-app.json
```

起動直後は`paused`です。標準入力から`start`、`pause`、`status`、`retry`、`quit`を送れます。`pause`と`quit`は録画中なら停止し、`discardAfterEachChunk`では完了画面のdiscardまで進めます。

複数台では一台につき一プロセスを起動し、`FAO_DEVICE_ID`と`FAO_WDA_LOCAL_PORT`を別にします。MJPEGにはWDAポートの1000番後を使うため、両方が他端末と重複しない値を割り当てます。

## 検証

```sh
swift test --package-path mac/controller-core
swift test --package-path apps/minute-app
```

テストは本番のアダプターとDevice Workerを直接通し、30分相当の自然終了後にdiscardして次のチャンクへ進むこと、任意停止時にもdiscardしてホームへ戻ること、未知画面や重複要素では一度もタップしないことを確認します。
