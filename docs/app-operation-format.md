# 操作定義の形式

操作定義は、撮影アプリの画面を「状態」として列挙し、状態間を結ぶタップを「操作」として記述したJSONです。`field-app`は、現在の状態から目標状態までの経路を操作定義から計算し、1操作ずつ実行します（[アーキテクチャ](architecture.md)）。

コード上は`OperationDefinition`型に対応します。サンプルは`apps/<アプリ名>/definition.example.json`にあります。

## 全体の構造

| キー | 内容 |
| --- | --- |
| `identifier` | ログや操作IDに使用する短い識別名 |
| `displayName` | 表示名 |
| `bundleIdentifier` | 対象アプリのBundle Identifier |
| `afterRecording` | 録画終了時の処理。保存（`save`）または破棄（`discard`） |
| `states` | 状態の一覧 |
| `actions` | 操作の一覧 |
| `appTransitions` | アプリによる自動遷移の一覧 |
| `goals` | 撮影継続（`running`）と停止（`paused`）のそれぞれで到達すべき状態 |
| `systemAlerts` | 自動で閉じるiOSのアラートと、閉じる際にタップするボタン。省略時は、iOSのアラートが表示されると停止する |
| `recovery` | 未定義の画面から、アプリの再起動で復帰するかどうか。省略時は、未定義の画面で停止する |

## UI要素の指定方法

状態の識別条件と操作の対象は、次のキーでUI要素を指定します。

| キー | 内容 |
| --- | --- |
| `name` | アクセシビリティ識別子が一致する要素。React Nativeの`testID`はこの識別子になる。識別子のないテキストは、テキストそのものが識別子になる |
| `namePrefix` | アクセシビリティ識別子が指定の文字列で始まる要素 |
| `type` | 要素の種類（`Button`、`Other`、`StaticText`など）。同じ名前のテキストとボタンを区別する場合に使用する |
| `labelPrefix` | アクセシビリティラベルが指定の文字列で始まる要素 |

`name`と`namePrefix`は、どちらか一方を指定します。

## 状態

| キー | 内容 |
| --- | --- |
| `id` | 状態名 |
| `present` | すべて存在すべき要素 |
| `absent` | 1つも存在してはならない要素 |

読み取った画面がちょうど1つの状態に該当した場合に、その状態にあると判定します。ダイアログが表示されても背後の画面の要素は読み取れるため、背後の画面の状態には、ダイアログの文言を`absent`に指定して区別します。Minute Dataのサンプルでは、カウントダウン画面の状態に、その上に表示される確認ダイアログの文言を`absent`として指定しています。

```json
{
  "id": "countdown",
  "present": [{ "name": "record-pending" }],
  "absent": [{ "name": "Cancel the recording?", "type": "StaticText" }]
},
{
  "id": "cancel-countdown-dialog",
  "present": [{ "name": "Cancel the recording?", "type": "StaticText" }]
}
```

## 操作

| キー | 内容 |
| --- | --- |
| `id` | 操作名 |
| `from` | この操作を実行できる状態 |
| `tap` | タップする要素 |
| `search` | タップする要素が一覧内にあり、スクロールしないと表示されない場合の検索方法 |
| `to` | タップ後に遷移する状態 |
| `impact` | 操作の影響（`navigation`、`startsRecording`、`stopsRecording`、`deletesRecording`、`submitsRecording`） |

経路の計算に使用する操作は、`afterRecording`の設定によって変わります。`discard`の場合は`submitsRecording`の操作を使用しないため、保存のボタンはタップされません。`save`の場合は`deletesRecording`の操作を使用しないため、破棄のボタンはタップされません。保存のボタンと、その後の確認のボタンの両方に`submitsRecording`を指定します。

`search`には、`container`（スクロールする一覧）、`items`（一覧の項目）、`maxSwipes`（片方向へのスワイプの最大回数）を指定します。一覧の先頭に戻ってから下方向に検索し、見つからなければ上方向にも検索します。

## アプリによる自動遷移

`appTransitions`には、カウントダウン終了後に録画中になる、録画が上限時間で終了して録画完了画面になる、など、タップせずにアプリが行う遷移を記述します。`field-app`は、これを待機するかどうかの判断に使用します。経路の計算では、待機をタップによる遷移よりも高コストとして扱うため、停止の指示を受信している場合は、録画の終了を待たずに停止ボタンをタップします。

## 自動で閉じるiOSのアラート

`systemAlerts`の各項目には、`id`（操作名）、`textContains`（アラートの文言の一部）、`button`（タップするボタンの文言）を指定します。アラートの文言に`textContains`が含まれていれば、`button`をタップして閉じ、処理を継続します。記述のないアラートと、指定のボタンがないアラートでは、停止します。アラートの文言とボタンは、iPhoneの言語設定に合わせて記述します。

```json
"systemAlerts": [
  { "id": "close-low-battery-alert", "textContains": "バッテリー残量はあと", "button": "閉じる" }
]
```

## 未定義の画面からの復帰

`field-app`は、次の画面を未定義の画面として扱います。

- どの状態にも該当しない、または2つ以上の状態に該当する画面
- 状態には該当するが、タップ対象の要素が未定義のシートやダイアログに覆われている画面

未定義の画面では、タップを行いません。`recovery`を指定すると、アプリを再起動し、定義済みの画面から経路を再計算します。

| キー | 内容 |
| --- | --- |
| `relaunchUnless` | この要素が1つでも存在する画面では、再起動せずに停止する。録画中や録画終了直後など、再起動すると録画データが失われる画面の識別要素を指定する |

再起動後も未定義の画面のままであれば、停止します。

```json
"recovery": {
  "relaunchUnless": [{ "name": "record-screen" }]
}
```

## 検証

`--validate-definition`で、実機に接続せずに次の項目を検証します。

- 状態名と操作名に重複がない
- 操作と自動遷移が、定義済みの状態間を結んでいる
- `REPLACE_WITH_`で始まる値が残っていない
- `afterRecording`の設定のもとで、すべての状態から`running`と`paused`の両方に到達できる

最後の項目を満たさない定義は、いずれかの画面で行き止まりになります。エラーメッセージには、到達できない状態名が出力されます。

```sh
swift run --package-path mac/controller-core field-app --validate-definition config/local/minute.json
```
