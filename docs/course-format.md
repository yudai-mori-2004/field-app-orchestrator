# コース形式

アプリ別コースは、共通の`field-app`実行器へ「どの画面で、何を押し、次に何を待つか」を渡すJSONです。MinuteとClaruは同じ形式を使います。

## アプリと画面

- `identifier`: ログや操作IDに使う短い名前
- `displayName`: 運用者へ表示する名前
- `bundleIdentifier`: Appiumが起動するiOSアプリ
- `screenProofs`: `home`、`taskReady`、`recording`、`completionPending`を一意に証明する要素
- `blockers`: ログイン、権限、警告を検出する要素

四つの画面証明はそれぞれ一つ必要です。観測時に0状態または複数状態が一致した場合、実行器は操作しません。

## 操作

`actions`は、操作名、影響、タップ対象を定義します。影響は次のいずれかです。

- `navigation`
- `startsRecording`
- `stopsRecording`
- `deletesRecording`
- `submitsRecording`

操作対象が0件または複数件の場合はタップしません。`submitsRecording`は監査用の分類として存在しますが、現在のMinute・Claruコースには提出操作を入れていません。

## 遷移

`transitions`は、`running`または`paused`と現在画面の組に対し、次のいずれかを一つ指定します。

- `action`: `actionIdentifier`の操作を実行する
- `stable`: 現在状態を維持する
- `needsOperator`: 操作せず担当者確認へ移す

2目標状態×4画面の8組を一つずつ定義します。完了後にdiscardするか、提出するか、人を待つかは`completionPending`の遷移だけで切り替えられます。

## 検証

`REPLACE_WITH_`で始まる値は未設定として拒否されます。実機へ接続せずにコースを検証できます。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-course config/local/minute.json
```
