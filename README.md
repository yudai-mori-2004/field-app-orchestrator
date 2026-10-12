# Field App Orchestrator

Field App Orchestratorは、エゴセントリックデータ収集用モバイルアプリの反復操作を自動化するシステムです。現在の対象はMinute DataとClaru AIです。

どちらのアプリでも、撮影前のタスク選択、一定時間ごとの録画終了、次の撮影開始が必要です。本システムは、初回設定後の通常稼働ではヘッドマウントしたiPhoneを装着者が触らず、Mac側から開始・一時停止できる状態を目指します。

## 共通制御基盤とアプリ別の操作定義

端末への接続、開始・一時停止の受付、操作の直列化、切断処理は共通制御基盤が担当します。アプリごとの画面判定条件、操作対象、状態遷移はJSONの操作定義に記述します。共通の実行処理がその定義を読み、現在画面と目標状態に応じて次の操作を選びます。

MinuteとClaruにはそれぞれ操作定義を用意し、端末ごとに対象アプリの定義を割り当てます。対応アプリを追加するときは、既存の定義形式で表せる範囲で`apps/<app-name>/`に操作定義を追加します。

定義項目と検証規則は[アプリ別操作定義の形式](docs/app-operation-format.md)にまとめています。

## リポジトリ構成

```text
apps/
  minute-app/                    Minute Dataの操作定義と設定手順
  claru-app/                     Claru AIの操作定義と設定手順
mac/
  controller-core/               共通実行器、端末ワーカー、Appium接続
docs/                            通常フロー、運用、設計判断
tools/                           Appiumセットアップと公開前検査
```

一台につき一つのDevice Workerだけが操作権を持ちます。Mac UI、CLI、物理入力などはiPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。ワーカーは対象アプリの操作定義に従い、画面を再観測して既知の操作だけを直列実行します。

画面や操作対象を一意に判定できない場合、または操作定義に登録したログイン・権限・警告の要素を検出した場合は、その端末だけを停止します。タップの応答が失われた場合も自動再送せず、実画面の再確認を待ちます。

## 撮影の通常フロー

MinuteとClaruの操作定義例は、次の撮影ループを表します。

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

録画完了後の処理は、各アプリの操作定義で指定します。現在の定義例はdiscardを選び、提出を確定する操作は含めていません。discardは、それ以前にアプリが行ったアップロードを取り消す保証にはなりません。

## 開発と実行

```sh
npm run setup:appium
npm run doctor:appium
npm run appium
```

対象アプリの操作定義例を`config/local/`へコピーし、現在版アプリのアクセシビリティ識別子へ置き換えます。具体的な起動方法は[Minute Data](apps/minute-app/README.md)と[Claru AI](apps/claru-app/README.md)の設定手順にあります。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/minute.json
```

```sh
swift test --package-path mac/controller-core
swift build -c release --package-path mac/controller-core
```

## 現在地

- USB接続した実機で、AppiumからWebDriverAgentを起動・再利用できることは確認済みです。
- 一つの共通実行器がMinuteまたはClaruの操作定義を読み込めます。
- 完了後discard、自動再開、任意停止、未知画面、重複要素は、操作定義を読み込む共通処理を通るテストで確認しています。
- 実Minute・実Claruの録画とdiscardはまだ実行していません。各アプリの現在版で画面識別子を確定した後に実機確認します。
- Wi-Fi接続、二台同時運転、切断復旧、8時間連続運転は次の実機検証です。

## 公開リポジトリとしての扱い

端末ID、署名情報、対象タスク、診断出力、スクリーンショット、録画、ローカル設定はコミットしません。追跡ファイルは[`tools/check_public_tree.py`](tools/check_public_tree.py)で検査します。

公開されていることはコードの利用許諾を意味しません。ライセンスは未決定です。
