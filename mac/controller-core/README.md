# Controller Core

`field-app`のソースコードです。動作の仕組みは[アーキテクチャ](../../docs/architecture.md)を参照してください。このドキュメントでは、各コンポーネントの役割を説明します。

## コマンド（`Sources/FieldAppCLI`）

- `FieldAppCommand`: `field-app`のエントリーポイント。環境変数と操作定義を読み込み、下記のコンポーネントを構成して、ターミナルからの入力、背面タップの受信、バッテリー監視を実行する。実行中はMacのスリープを抑止し、イベントをタイムスタンプ付きでログに出力する
- `ControlServer`: 背面タップのショートカットからの`POST /start`と`POST /pause`を受信する。トークンを検証し、受け付けなかったリクエストは理由をログに出力する
- `WearerReplies`: 背面タップへの応答文（「撮影を開始します。」「撮影を終了します。」）

## 制御ライブラリ（`Sources/FieldAppControllerCore`）

- `DeviceWorker`（`CaptureControl.swift`）: iPhone 1台の目標状態（`running`または`paused`）を保持し、画面の読み取り、次の操作の決定、実行を1つずつ進める。要対応状態（`needsAttention`）や再接続中（`reconnecting`）などの状態も管理する。目標状態が変わるたびにイベントを通知する
- `OperationDefinition`、`OperationDefinitionAdapter`（`OperationDefinition.swift`）: 操作定義のJSONを読み込み、検証する。読み取ったUI要素から画面の状態を特定し、目標状態までの経路を計算して次の操作を返し、タップを実行する。未定義の画面で撮影アプリを再起動するかどうかもここで判断する
- `WebDriverAgentSession`（`WebDriverAgentSession.swift`）: iPhoneのWebDriverAgentとHTTPで通信する。UI要素の検索、タップ、スクロール、撮影アプリの前面表示と再起動、ロック解除、iOSのアラート、バッテリー情報の取得を行う。接続できない場合は、一定間隔で再接続する
- `XcodeWebDriverAgentHost`（同上）: `devicectl`でiPhoneの接続先を取得し、WebDriverAgentが応答しない場合に`xcodebuild`で起動する
- `ElementSelector`、`AutomationElement`、`AppAutomationSession`（`Automation.swift`）: UI要素の指定方法と、iPhoneを操作するインターフェースの定義。テストでは、このインターフェースをモックに差し替える
- `BatteryGuard`: 充電していない状態で、バッテリー残量が設定値まで低下したかを判定する
- `InstructionRecord`: 目標状態をMacのディスクに保存し、`field-app`の異常終了後に引き継ぐ
- `Doorbell`: 画面の読み取り間隔の待機を、指示の受信時に中断する

## テスト

```sh
swift test
```

- `OperationDefinitionTests`: Minute Dataの操作定義のサンプルを、Minuteのモック（`FakeMinuteApp`）に対して実行する。どの画面から開始しても両方の目標状態に到達すること、ダイアログやシートに覆われたボタンをタップしないこと、などを検証する
- `DeviceWorkerTests`: 目標状態の切り替え、要対応状態の扱い、終了処理を、画面を簡略化したモックで検証する
- `WebDriverAgentSessionTests`: WebDriverAgentの応答を差し替え、再接続、WebDriverAgentの起動、応答の解釈を検証する
- `InstructionRecordTests`、`DoorbellTests`: 各コンポーネント単体の動作を検証する
