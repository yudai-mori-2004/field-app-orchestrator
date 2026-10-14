# Minute Data

Minute Data用の操作定義のサンプル（`definition.example.json`）です。UI要素の識別子とボタンは、Minute 1.29.0で確認した値です。MinuteのアップデートでUI要素が変わった場合は、この定義を修正してください。

使用する際は、撮影するタスクの名前を設定して`config/local/`にコピーします。手順は[セットアップ](../../docs/setup.md#5-操作定義の作成)を参照してください。

画面の文言は、Minuteの表示言語が英語の場合のものです。バッテリー残量のアラートの文言は、iPhoneの言語設定が日本語の場合のものです。

## 定義済みの画面

| 状態 | 画面 |
| --- | --- |
| `tasks` | タスク一覧のタブ |
| `minutes` | Minutesのタブ |
| `settings` | Settingsのタブ |
| `assigned-task-card` | 撮影対象のタスクカード。停止時は、カメラを閉じてこの画面で待機する |
| `other-task-card` | 他のタスクのタスクカード |
| `armed` | カメラが起動し、録画ボタンが表示された画面 |
| `countdown` | 録画開始前のカウントダウン |
| `cancel-countdown-dialog` | カウントダウン中のキャンセルで表示される確認ダイアログ（Cancel the recording?） |
| `recording` | 録画中。撮影継続時の目標状態 |
| `too-short-dialog` | 1分未満で録画を停止したときのダイアログ（Recording too short） |
| `time-limit-dialog` | 30分の上限到達のダイアログ（Maximum time limit reached） |
| `review` | 録画完了画面。保存か破棄を選択する |
| `save-dialog` | 保存の確認ダイアログ（Save this Minute?） |
| `discard-dialog` | 破棄の確認ダイアログ（Discard this recording?） |
| `saved` | 保存後の画面 |

録画が30分で区切られると、`recording` → `time-limit-dialog` → `review`の順に遷移します。その後、破棄する場合は`discard-dialog` → `armed`、保存する場合は`save-dialog` → `saved` → `armed`と遷移し、録画ボタンのタップで`countdown` → `recording`に戻ります。保存と破棄のどちらを行うかは`afterRecording`で指定します。サンプルは破棄（`discard`）です。

撮影対象のタスクは、タスク一覧から名前で検索します。一覧をスクロールしながら検索するため、40〜50秒かかる場合があります。撮影継続中はタスク一覧に戻らないため、検索が発生するのは、画面操作の後やMinuteの再起動後のみです。

## 再起動しない画面

未定義の画面では、`field-app`はMinuteを再起動し、タスク一覧から処理を再開します。ただし、`record-screen`要素が存在する画面（カメラや録画の画面）では、再起動せずに停止します。再起動すると、録画途中のデータと、録画完了画面で保存または破棄を待っている録画が失われるおそれがあるためです。

## 実機で確認したMinuteの挙動

- ホーム画面や他のアプリに移ると、録画を停止する。1分未満の録画は破棄してタスクカードに戻り、1分以上の録画は録画完了画面に残る
- 画面がロックされると、録画を停止して録画完了画面に遷移する
- コントロールセンターを開いても、録画を継続する
- 30分の上限に達すると、録画を停止し、録画完了画面の上に上限到達のダイアログを表示する
- カウントダウン中にキャンセルをタップすると、確認ダイアログを表示し、カウントダウンを中断して待機する。「Keep going」でカウントダウンを再開し、「Yes, cancel」でタスクカードに戻る
- カメラへのアクセス許可がない場合、録画開始時にアクセス許可を求めるシート（Camera access needed）を表示する
