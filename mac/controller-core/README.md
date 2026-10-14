# Controller Core

`field-app`のコードです。動き方の説明は[仕組み](../../docs/architecture.md)にあり、ここではどの部品がどこを受け持っているかを書きます。

## `field-app`のコマンド（`Sources/FieldAppCLI`）

- `FieldAppCommand`: `field-app`の入口。環境変数と操作定義を読み、下の部品を組み立てて、ターミナルの入力、背面タップの受け口、電池の見張りを動かす。動いている間はMacのスリープを防ぎ、出来事を時刻つきで記録に出す
- `ControlServer`: 背面タップのショートカットからの`POST /start`と`POST /pause`を受ける。トークンを確かめ、受け付けなかった要求は理由を記録に出す
- `WearerReplies`: 背面タップに返す文（「撮影を開始します。」「撮影を終了します。」）

## 判断と操作（`Sources/FieldAppControllerCore`）

- `DeviceWorker`（`CaptureControl.swift`）: iPhone 1台の目標（`running`か`paused`）を持ち、画面を読み、次の一歩を決め、実行する、を一つずつ進める。止まった（`needsAttention`）、つなぎ直している（`reconnecting`）、などの様子もここが持つ。目標が変わるたびに知らせる
- `OperationDefinition`と`OperationDefinitionAdapter`（`OperationDefinition.swift`）: 操作定義のJSONを読み、検証する。読み取った部品から画面の状態を一つに決め、目標までの道順を計算して次の一歩を返し、ボタンを押す。知らない画面から撮影アプリを起動し直すかどうかもここで決める
- `WebDriverAgentSession`（`WebDriverAgentSession.swift`）: iPhoneのWebDriverAgentとHTTPで話す。部品の検索、タップ、スクロール、撮影アプリを前面に戻す操作と起動し直す操作、ロックの解除、iOSの警告、電池を扱う。つながらないときは、決めた間隔でつなぎ直す
- `XcodeWebDriverAgentHost`（同じファイル）: `devicectl`でiPhoneの宛先を調べ、WebDriverAgentが返事をしないときに`xcodebuild`で起動する
- `ElementSelector`、`AutomationElement`、`AppAutomationSession`（`Automation.swift`）: 画面の部品の選び方と、iPhoneを操作する口の取り決め。テストでは、この口を模擬のiPhoneに差し替える
- `BatteryGuard`: 充電していない間に、電池が決めた残量まで減ったかを判断する
- `InstructionRecord`: 目標をMacのディスクに残し、`field-app`が落ちたあとに引き継ぐ
- `Doorbell`: 画面を読む間隔の待ちを、指示が届いたときに切り上げる

## テスト

```sh
swift test
```

- `OperationDefinitionTests`: Minute Dataの操作定義の例を、模擬のMinute（`FakeMinuteApp`）に対して動かす。どの画面から始めても両方の目標に着くこと、ダイアログやシートに覆われたときに押さないこと、などを確かめる
- `DeviceWorkerTests`: 目標の切り替え、止まったときの扱い、終了の流れを、画面を単純にした模擬のアプリで確かめる
- `WebDriverAgentSessionTests`: WebDriverAgentの返事を差し替え、つなぎ直し、WebDriverAgentの起動、返事の読み方を確かめる
- `InstructionRecordTests`、`DoorbellTests`: それぞれの部品だけを確かめる
