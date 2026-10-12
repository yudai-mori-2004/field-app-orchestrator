# Field App Orchestrator

Field App Orchestratorは、エゴセントリックデータ収集用モバイルアプリの反復操作を自動化するシステムです。現在の対象はMinute DataとClaru AIです。

どちらのアプリでも、撮影前のタスク選択、一定時間ごとの録画終了、次の撮影開始が必要です。本システムは、初回設定後の通常稼働ではヘッドマウントしたiPhoneを装着者が触らず、Mac側から開始・一時停止できる状態を目指します。

## エンジンとコース

共通部分は、ゲームエンジンとコースの関係に分けています。

```text
共通エンジン
  ├─ Appium / WebDriverAgent接続
  ├─ iPhoneごとのDevice Worker
  ├─ running / paused入力
  ├─ 操作の直列化と切断処理
  └─ 未知画面での安全停止

アプリ別コース
  ├─ minute-app/course.json
  └─ claru-app/course.json
       ├─ bundle identifier
       ├─ 各画面を証明する要素
       ├─ タップ対象と操作の影響
       └─ 目標状態ごとの遷移
```

MinuteとClaruは別のエンジンや製品ではなく、同じ実行器に読み込ませる二つのコースです。新しい収集アプリを追加するときも、通常はSwiftコードを複製せず、新しい`apps/<app-name>/course.json`を追加します。

コースのフィールドと検証規則は[`docs/course-format.md`](docs/course-format.md)にまとめています。

## リポジトリ構成

```text
apps/
  minute-app/                    Minute Dataのコース
  claru-app/                     Claru AIのコース
mac/
  controller-core/               共通実行器、端末ワーカー、Appium接続
docs/                            通常フロー、運用、設計判断
tools/                           Appiumセットアップと公開前検査
```

一台につき一つのDevice Workerだけが操作権を持ちます。Mac UI、CLI、物理入力などはiPhoneへ直接タップを送らず、`running`または`paused`という目標状態を更新します。ワーカーは選択されたコースを読み、画面を再観測して既知の操作だけを直列実行します。

画面証明や操作対象が0件または複数件の場合、ログイン・権限・警告・未知画面の場合は、その端末だけを停止します。タップの応答が失われた場合も自動再送せず、実画面の再確認を待ちます。

## コースの通常フロー

MinuteとClaruの初期コースは、同じ撮影ループを表します。

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

discard、保持、提出のどれを実行するかもコースの最後の遷移です。提出を確定する操作はまだどちらのコースにも入れていません。discardは、それ以前にアプリが行ったアップロードを取り消す保証にはなりません。

## 開発と実行

```sh
npm run setup:appium
npm run doctor:appium
npm run appium
```

対象アプリのコース例を`config/local/`へコピーし、現在版アプリのアクセシビリティ識別子へ置き換えます。具体的な起動方法は[Minute course](apps/minute-app/README.md)と[Claru course](apps/claru-app/README.md)にあります。

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
- 一つの共通実行器がMinuteまたはClaruのコースを読み込めます。
- 完了後discard、自動再開、任意停止、未知画面、重複要素は、共通コース実行器を通るテストで確認しています。
- 実Minute・実Claruの録画とdiscardはまだ実行していません。各アプリの現在版で画面識別子を確定した後に実機確認します。
- Wi-Fi接続、二台同時運転、切断復旧、8時間連続運転は次の実機検証です。

## 公開リポジトリとしての扱い

端末ID、署名情報、対象タスク、診断出力、スクリーンショット、録画、ローカル設定はコミットしません。追跡ファイルは[`tools/check_public_tree.py`](tools/check_public_tree.py)で検査します。

公開されていることはコードの利用許諾を意味しません。ライセンスは未決定です。
