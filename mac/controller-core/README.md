# Controller Core

Mac側で、iPhone 1台分の操作を受け持つ部分です。

`DeviceWorker`は、`running`または`paused`という目標の状態を持ち、`CaptureAppAdapter`から現在の画面と次の操作を受け取って、操作を一つずつ実行します。開始や一時停止の指示はタップに直接変えず、目標の状態を書き換えるだけです。終了するときは`pauseAndStop()`で一時停止まで進めてから止めます。送った操作の途中なら、それが終わるのを待ちます。

`CaptureCourseAdapter`は、アプリ別の操作定義（JSON）を読み込み、画面の判定、次の操作の選択、タップを行います。`CaptureAppAdapter`の実装として`DeviceWorker`から呼ばれます。

`AppiumSession`は、iPhone上のWebDriverAgentとのセッションを作り、アクセシビリティ要素の検索とタップを行います。端末ごとのポート、UDID、署名チームは起動時に与えます。

画面を一つに決められないとき、操作定義に登録したログイン・権限の確認・警告の画面が出たとき、タップの結果がわからなくなったときは`needsAttention`になり、人が確認して再開するまで操作しません。

```sh
swift test
```

操作定義の例と起動方法は、[Minute Data](../../apps/minute-app/README.md)と[Claru AI](../../apps/claru-app/README.md)の設定手順にあります。
