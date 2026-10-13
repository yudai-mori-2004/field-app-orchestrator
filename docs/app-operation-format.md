# アプリ別操作定義の形式

アプリ別操作定義は、対象アプリの画面を「状態」として並べ、状態どうしをつなぐタップを「操作」として書いたJSONです。共通の実行処理は、今の状態から目標の状態までの道順をこの地図から計算し、一歩ずつ操作します。手順の並びは書きません。

実装上は`OperationDefinition`型に対応します。例は`apps/<アプリ名>/definition.example.json`にあります。

## 全体

- `identifier`: ログや操作IDに使う短い名前
- `displayName`: 表示用の名前
- `bundleIdentifier`: 対象アプリのbundle identifier
- `afterRecording`: 録画が終わったときに保存するか破棄するか（`save`または`discard`）
- `states`: 状態の一覧
- `actions`: 操作の一覧
- `appTransitions`: アプリが自分で進む移り変わり
- `goals`: `running`（撮影を続ける）と`paused`（止める）のそれぞれで、たどり着けばよい状態
- `systemAlerts`: 閉じてよいiOSの警告と、閉じるボタン。省略すると、警告が出たら人を待つ
- `recovery`: 知らない画面から、アプリを起動し直して戻るかどうか。省略すると起動し直さない

## 部品の選び方

状態の目印と操作の対象は、次の項目で画面の部品を選びます。

- `name`: アクセシビリティの名前が一致する部品。React Nativeの`testID`はこの名前になり、識別子のない文字は文字そのものが名前になる
- `namePrefix`: 名前がこの文字で始まる部品
- `type`: 部品の種類（`Button`、`Other`、`StaticText`など）。同じ名前の文字とボタンを分けるときに使う
- `labelPrefix`: 読み上げ用の文字列がこの文字で始まる部品

`name`と`namePrefix`はどちらか一方を書きます。

## 状態

- `id`: 状態の名前
- `present`: すべて画面にあるべき部品
- `absent`: 一つも画面にあってはならない部品

読み取った画面にちょうど一つの状態が当てはまれば、その状態にいると判断します。ダイアログが開いても下の画面の部品は読み取れてしまうので、下の画面の状態にはダイアログの文言を`absent`として書き、区別します。

## 操作

- `id`: 操作の名前
- `from`: この操作を使える状態
- `tap`: 押す部品
- `search`: 押す部品が一覧の中にあり、スクロールしないと現れないときの探し方
- `to`: 押した後に移る状態
- `impact`: 操作の影響（`navigation`、`startsRecording`、`stopsRecording`、`deletesRecording`、`submitsRecording`）

`afterRecording`が`discard`なら`submitsRecording`の操作を、`save`なら`deletesRecording`の操作を、道順に使いません。保存のボタンと、その後の確認ボタンの両方に`submitsRecording`を付けます。

`search`は、`container`（スクロールする一覧）、`items`（一覧の項目）、`maxSwipes`（片方向に動かす最大回数）を持ちます。一覧の先頭に戻ってから下へ探し、見つからなければ上へも探します。

## アプリが自分で進む移り変わり

`appTransitions`には、カウントダウンが終わって録画中になる、録画が上限の長さで終わって完了画面になる、のように、押さなくてもアプリが進む移り変わりを書きます。実行処理は、これを待つかどうかの判断にだけ使います。待つことは押して進むより重く数えるので、止める指示が出ているときは、録画が終わるのを待たずに停止を押します。

## 閉じてよいiOSの警告

`systemAlerts`の各項目は、`id`（操作の名前）、`textContains`（警告の文の一部）、`button`（押すボタンの文字）を持ちます。警告の文に`textContains`が含まれていれば`button`を押して閉じ、続きを進めます。書いていない警告と、書いたボタンがない警告では、人を待ちます。警告の文とボタンはiPhoneの言語で書きます。

```json
"systemAlerts": [
  { "id": "close-low-battery-alert", "textContains": "バッテリー残量はあと", "button": "閉じる" }
]
```

## 知らない画面から戻る

実行処理は、次の画面を知らない画面として扱います。

- どの状態にも当てはまらない、または二つ以上の状態に当てはまる画面
- 状態には当てはまるが、押す部品が定義にないシートやダイアログに覆われている画面

知らない画面のボタンは押しません。`recovery`があれば、アプリを起動し直して、知っている画面から道順を決め直します。

- `relaunchUnless`: この部品が一つでも画面にあるときは起動し直さず、人を待つ。録画中や録画を終えた直後のように、起動し直すと撮ったものが失われる画面の目印を書く

起動し直しても知らない画面のままなら、人を待ちます。

```json
"recovery": {
  "relaunchUnless": [{ "name": "record-screen" }]
}
```

## 検証

`--validate-definition`で、実機につながずに次を確かめます。

- 状態と操作の名前が重複していない
- 操作と移り変わりが、定義された状態の間を結んでいる
- `REPLACE_WITH_`で始まる値が残っていない
- `afterRecording`の方針のもとで、すべての状態から`running`と`paused`の両方へたどり着ける

最後の項目が通らない定義は、どこかの画面で行き止まりになります。エラーには、たどり着けない状態の名前が出ます。

```sh
swift run --package-path mac/controller-core field-app \
  --validate-definition config/local/minute.json
```
