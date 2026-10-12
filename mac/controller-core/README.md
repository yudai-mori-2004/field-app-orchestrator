# Controller Core

Controller Coreは、Mac側で一台のiPhoneに対する操作を直列化する状態機械です。Macアプリ、CLI、物理ボタンなどの入力は、iPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。

`DeviceWorker`は`CaptureAppAdapter`から現在画面を観測し、最新の目標状態へ近づくために必要な操作だけを一つずつ実行します。30分チャンクが自然終了してホームへ戻った場合も、目標状態が`running`なら次のチャンクを開始できます。

ログイン、権限要求、警告、未知の画面は`needsAttention`になり、オペレーターが確認するまで操作を再開しません。

```sh
swift test
```

現在は状態機械とインメモリアダプターのテストまでです。実機接続では`CaptureAppAdapter`をAppium XCUITest Driverの長時間WebDriverAgentセッションへ接続します。署名チーム、端末UDID、対象アプリの割り当てはローカル設定で与え、コミットしません。
