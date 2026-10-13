# Controller Core

Mac側で、iPhone 1台分の操作を受け持つ部分です。

`DeviceWorker`は、`running`または`paused`という目標の状態を持ち、`CaptureAppAdapter`に画面の読み取り、次の一歩の判断、操作の実行を任せて、一歩ずつ進めます。開始や止める指示はタップに直接変えず、目標の状態を書き換えるだけです。終了するときは`pauseAndStop()`で止めた状態まで進めてから止めます。送った操作の途中なら、それが終わるのを待ちます。

`OperationDefinitionAdapter`は、アプリ別の操作定義（JSON）を読み込み、画面の状態の判定、目標までの道順の計算、タップを行います。

`WebDriverAgentSession`は、iPhone上のWebDriverAgentとネットワーク越しに直接セッションを作り、画面の中央にあるアプリの部品の検索、タップ、スクロール、アプリを前面に戻す操作と起動し直す操作を行います。iPhoneの宛先とWebDriverAgentの起動は`XcodeWebDriverAgentHost`が受け持ち、`devicectl`と`xcodebuild`を使います。iPhoneに届くのにWebDriverAgentが返事をしないときだけ起動し直し、届かない間は待ちます。

どの状態にも当てはまらない画面と、押す部品が何かに覆われた画面は、操作定義が許していればアプリを起動し直して戻ります。操作定義に書いたiOSの警告は、書いたボタンで閉じます。戻れないとき、書いていない警告、解除できないロック、iPhoneがコマンドを断ったときは`needsAttention`になり、人が確認して再開するまで操作しません。WebDriverAgentとの接続が失敗したときは`reconnecting`になり、10秒おきにつなぎ直して、新しい読み取りから続けます。

`BatteryGuard`は、充電していない状態で電池が決めた残量まで減ったときに、一度だけ止める判断を返します。

```sh
swift test
```

操作定義の例と起動方法は、[Minute Data](../../apps/minute-app/README.md)と[Claru AI](../../apps/claru-app/README.md)の設定手順にあります。
