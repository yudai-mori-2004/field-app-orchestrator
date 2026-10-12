# Mock Task App

Mock Task Appは、第三者アプリへ録画を提出せずにオーケストレーターを実機検証するためのiPhoneアプリです。Minute Dataのコード、画像、文言、ネットワーク処理は含みません。自動化に必要な画面状態とアクセシビリティ識別子だけを再現します。

アプリにはカメラ、ファイル保存、ネットワーク通信の実装がありません。常に`MOCK — NO RECORDING OR UPLOAD`と表示します。

## 通常動作

1. `home-screen`で`featured-card-mock-task`を選ぶ。
2. `record-screen`で`record-start-task`を押す。
3. `recording-screen`でカウントダウンする。
4. 30分後、自動的に`home-screen`へ戻る。

UIテスト時は起動引数で時間を短縮できます。

```swift
app.launchArguments = ["-mockDurationSeconds", "3"]
```

## 実機へのビルド

```sh
xcodebuild \
  -project MockTaskApp.xcodeproj \
  -scheme MockTaskApp \
  -destination 'id=<IPHONE_UDID>' \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  build
```

署名チームと端末UDIDはコマンドまたはローカルXcode設定で与え、コミットしません。
