# アプリ別操作定義の形式

アプリ別操作定義は、対象アプリ、画面判定条件、操作対象、状態遷移を記述するJSONです。MinuteとClaruは同じ形式を使い、共通の`field-app`実行器が現在画面と目標状態に応じて操作を選びます。

実装上は`CaptureCourseDefinition`型に対応し、`--course`で実行対象のJSONを指定します。定義例のファイル名は`course.example.json`です。

## アプリと画面

- `identifier`: ログや操作IDに使う短い名前
- `displayName`: 運用者へ表示する名前
- `bundleIdentifier`: Appiumが起動するiOSアプリ
- `screenProofs`: `home`、`taskReady`、`recording`、`completionPending`を一意に証明する要素
- `blockers`: ログイン、権限、警告を検出する要素

四つの画面証明はそれぞれ一つ必要です。観測時に0状態または複数状態が一致した場合、実行器は操作しません。

`blockers`に登録した要素を検出すると、画面判定やタップに進まず、操作を止めて人の確認を待ちます。定義例の`blockers`は空です。対象アプリで確かめたログイン、権限の確認、警告の要素を登録します。

## 操作

`actions`は、操作名、影響、タップ対象を定義します。影響は次のいずれかです。

- `navigation`
- `startsRecording`
- `stopsRecording`
- `deletesRecording`
- `submitsRecording`

操作対象が0件または複数件の場合はタップしません。

## 遷移

`transitions`は、`running`または`paused`と現在画面の組に対し、次のいずれかを一つ指定します。

- `action`: `actionIdentifier`の操作を実行する
- `stable`: 現在状態を維持する
- `needsOperator`: 操作せず、人の確認を待つ

2目標状態×4画面の8組を一つずつ定義します。完了後に破棄するか、提出するか、人の確認を待つかは`completionPending`の遷移で指定します。新しい完了操作を選ぶ場合は、対応する操作も`actions`へ定義します。

## 検証

`REPLACE_WITH_`で始まる値は未設定として拒否されます。実機へ接続せずに操作定義を検証できます。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/minute.json
```
