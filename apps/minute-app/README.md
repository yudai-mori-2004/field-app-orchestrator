# Minute Data

Minute Dataを操作するための操作定義の例（`definition.example.json`）です。画面の目印とボタンは、Minute 1.29.0で確かめた値です。Minuteが更新されて画面の部品が変わったら、この定義を直します。

使うときは、撮るタスクの名前を入れて`config/local/`にコピーします。手順は[セットアップ](../../docs/setup.md#5-操作定義を用意する)にあります。

画面の文は、Minuteの表示が英語のときのものです。電池残量の警告の文は、iPhoneの言語が日本語のときのものです。

## 定義が知っている画面

| 状態 | 画面 |
| --- | --- |
| `tasks` | タスク一覧のタブ |
| `minutes` | Minutesのタブ |
| `settings` | Settingsのタブ |
| `assigned-task-card` | 撮るタスクの説明カード。止めたときは、カメラを切ってこの画面で待つ |
| `other-task-card` | ほかのタスクの説明カード |
| `armed` | カメラが開き、録画ボタンが出ている画面 |
| `countdown` | 録画が始まる前のカウントダウン |
| `cancel-countdown-dialog` | カウントダウン中に取り消しを押すと出る確認（Cancel the recording?） |
| `recording` | 録画中。撮影を続けるときは、この画面を目指す |
| `too-short-dialog` | 1分未満で録画を止めたときのダイアログ（Recording too short） |
| `time-limit-dialog` | 30分の上限に達したお知らせ（Maximum time limit reached） |
| `review` | 完了画面。保存か破棄を選ぶ |
| `save-dialog` | 保存の確認（Save this Minute?） |
| `discard-dialog` | 破棄の確認（Discard this recording?） |
| `saved` | 保存したあとの画面 |

録画が30分で区切られると、`recording` → `time-limit-dialog` → `review` と進みます。そこから、破棄するときは `discard-dialog` → `armed`、保存するときは `save-dialog` → `saved` → `armed` と進み、録画ボタンを押して `countdown` → `recording` に戻ります。どちらにするかは`afterRecording`で選びます。例は破棄（`discard`）です。

撮るタスクは、タスク一覧の中から名前で探します。一覧をスクロールしながら探すので、40〜50秒かかることがあります。撮影を続けている間は一覧に戻らないので、探すのは、画面を触られたあとや、Minuteを起動し直したあとだけです。

## 起動し直さない画面

操作定義にない画面にいるとき、`field-app`はMinuteを起動し直して、タスク一覧から進めます。ただし、`record-screen`という部品がある画面（カメラや録画の画面）では、起動し直さずに止まります。起動し直すと、撮りかけの録画と、完了画面で保存か破棄を待っている録画が失われるおそれがあるためです。

## 実機でわかったMinuteの動き

- ホーム画面やほかのアプリに移ると、Minuteは録画を止める。1分未満の録画は破棄して説明カードに戻り、1分以上の録画は完了画面に残す
- 画面がロックされると、Minuteは録画を止めて完了画面に移る
- コントロールセンターを開いても、Minuteは録画を続ける
- 30分の上限に達すると、録画を止め、完了画面の上に上限のお知らせを出す
- カウントダウン中に取り消しを押すと、確認を出し、カウントダウンを止めて待つ。「Keep going」でカウントダウンを続け、「Yes, cancel」で説明カードに戻る
- カメラの許可がないと、録画を始めるときに許可を求めるシート（Camera access needed）を出す
