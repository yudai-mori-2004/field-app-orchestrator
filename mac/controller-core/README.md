# Controller Core

Controller Coreは、Mac側で一台のiPhoneに対する操作を直列化する状態機械です。Macアプリ、CLI、物理ボタンなどの入力は、iPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。

`DeviceWorker`は`CaptureAppAdapter`から現在画面と次の一操作を受け取り、最新の目標状態へ近づく操作だけを一つずつ実行します。

`CaptureCourseAdapter`は、JSONのアプリ別操作定義を読み込み、画面判定、次の操作の選択、タップを行う共通実装です。`CaptureAppAdapter`インターフェースを通じてDevice Workerから呼び出されます。アプリごとのbundle identifier、画面判定条件、タップ対象、状態遷移は操作定義に記述します。

`AppiumSession`は、実機上のWebDriverAgentセッションを作り、アクセシビリティ要素の検索とタップを行う共通HTTP接続です。端末ごとのポート、UDID、署名Teamは起動時に与えます。

画面を一意に判定できない場合、または操作定義に登録したログイン・権限要求・警告の要素を検出した場合は`needsAttention`になり、オペレーターが確認するまで操作を再開しません。

```sh
swift test
```

操作定義例は[`apps/minute-app`](../../apps/minute-app/README.md)と[`apps/claru-app`](../../apps/claru-app/README.md)にあります。署名チーム、端末UDID、対象タスク、実機から確認した識別子はローカル設定で与え、コミットしません。

```sh
swift run --package-path mac/controller-core field-app --course config/local/minute.json
```
