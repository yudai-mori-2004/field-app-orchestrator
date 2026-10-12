# Controller Core

Controller Coreは、Mac側で一台のiPhoneに対する操作を直列化する状態機械です。Macアプリ、CLI、物理ボタンなどの入力は、iPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。

`DeviceWorker`は`CaptureAppAdapter`から現在画面と次の一操作を受け取り、最新の目標状態へ近づく操作だけを一つずつ実行します。

`CaptureCourseAdapter`は、MinuteまたはClaruのJSONコースを共通の`CaptureAppAdapter`として実行します。アプリごとのbundle identifier、画面証明、タップ対象、状態遷移はコース側へ置きます。

`AppiumSession`は、実機上のWebDriverAgentセッションを作り、アクセシビリティ要素の検索とタップを行う共通HTTP接続です。端末ごとのポート、UDID、署名Teamは起動時に与えます。

ログイン、権限要求、警告、未知の画面は`needsAttention`になり、オペレーターが確認するまで操作を再開しません。

```sh
swift test
```

コースは[`apps/minute-app`](../../apps/minute-app/README.md)と[`apps/claru-app`](../../apps/claru-app/README.md)にあります。署名チーム、端末UDID、対象タスク、実機から確認した識別子はローカル設定で与え、コミットしません。

```sh
swift run --package-path mac/controller-core field-app --course config/local/minute.json
```
