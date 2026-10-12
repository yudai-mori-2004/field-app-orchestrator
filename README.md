# Field App Orchestrator

Field App Orchestratorは、現場のMacから複数のiPhoneを個別に監視し、販売先アプリで繰り返し必要になる操作を補助するシステムです。初回設定後の通常稼働では、ヘッドマウントしたiPhoneを装着者が触らず、Mac側から開始・一時停止できる状態を目指します。

一台につき一つのDevice Workerだけが操作権を持ちます。Mac UI、CLI、物理入力などはiPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。ワーカーは画面を再観測して既知の操作だけを直列実行し、対象要素を一意に確認できない場合や未知の画面では、その端末だけを停止します。

## 実装単位

```text
apps/
  minute-app/                    Minute Data本番アダプターとCLI
mac/
  controller-core/               端末ワーカーとAppium HTTP接続
docs/                            通常フロー、運用、設計判断
tools/                           Appiumセットアップと公開前検査
```

新しい販売先アプリは`apps/<app-name>/`へ独立して追加します。bundle identifier、画面状態、操作対象、状態遷移は各アプリ側に置き、端末接続、操作の直列化、開始・一時停止、監査可能な操作種別は共通層に置きます。仕様がないアプリの空実装や汎用DSLは作りません。

## Minute Data

[`apps/minute-app`](apps/minute-app/README.md)には、Minute Dataの次の経路があります。

```text
running
  → 割り当て済みタスクを開く
  → 録画を開始する
  → 完了画面でdiscardする
  → 次のチャンクを開始する

paused
  → 録画中なら停止する
  → 完了画面でdiscardする
  → ホームで待機する
```

完了時の挙動は`MinuteCompletionPolicy`に閉じ込めています。現時点では`discardAfterEachChunk`と、操作せず停止する`requireOperator`だけを実装し、提出を確定する操作は実装していません。

Minute Dataは録画中または完了前からアップロードする可能性があります。したがって、最後にdiscardすることは「データがサーバーへ一度も送られない」ことの保証にはなりません。実アプリでの確認は対象タスクと影響を確定してから行います。

## 開発と実行

Node.js、Appium、XCUITest Driverの版は固定しています。

```sh
npm run setup:appium
npm run doctor:appium
npm run appium
```

Minuteの端末別起動と設定方法は[`apps/minute-app/README.md`](apps/minute-app/README.md)を参照してください。

```sh
swift test --package-path mac/controller-core
swift test --package-path apps/minute-app
```

## 現在地

- USB接続した実機で、AppiumからWebDriverAgentを起動・再利用できることは確認済みです。
- 複数端末の操作を一台ずつ独立したワーカーへ分ける境界があります。
- 観測中のセッション切断は一度だけ再接続し、結果不明のタップは自動再送しません。
- Minuteの完了後discard、自動再開、任意停止は、本番アダプターを通る決定論的テストで確認しています。
- 実Minuteの録画・discard操作はまだ実行していません。画面識別子を現在版で確定した後に実機確認します。
- Wi-Fi接続、切断復旧、二台同時運転、8時間連続運転は次の実機検証です。

## 公開リポジトリとしての扱い

端末ID、署名情報、対象タスク、診断出力、スクリーンショット、録画、ローカル設定はコミットしません。追跡ファイルは[`tools/check_public_tree.py`](tools/check_public_tree.py)で検査し、pushとpull requestでも同じ検査を実行します。

公開されていることはコードの利用許諾を意味しません。ライセンスは未決定です。
