# アーキテクチャ

## 通常フロー

Mac上では、登録済みiPhoneごとに一つのDevice Workerと一つのAppiumセッションを起動します。各ワーカーには、操作対象アプリのコース定義を一つ割り当てます。

```text
Controller
  ├─ Device Worker A ── Course Engine ── Minute course ── iPhone A
  ├─ Device Worker B ── Course Engine ── Minute course ── iPhone B
  └─ Device Worker C ── Course Engine ── Claru course  ── iPhone C
```

MinuteとClaruは別の実行基盤ではありません。どのアプリを起動し、どの画面を確認し、次に何を押すかを表したコースだけが異なります。

ユーザーの開始・一時停止は、iPhoneへ直結したタップ命令ではなく、端末ごとの`running`または`paused`という目標状態です。Device Workerは現在画面と最新の目標状態をCourse Engineへ渡し、コースが返した一操作を直列に実行します。

## 責務

### Controller

- 登録端末、対象アプリ、コースの割り当て
- 端末ごとのワーカープロセス起動・停止
- 状態、経過時間、再開回数、要対応状態の表示
- 全体または個別の開始・一時停止・再試行
- UI、CLI、物理入力から来た目標状態の統合

現段階では共通の`field-app` CLIを一台につき一プロセス起動し、`--course`でMinuteまたはClaruを選びます。複数端末を束ねるGUIはこの境界の上へ追加します。

### Device Worker

- 一台分の操作を直列化する
- 最新の目標状態だけを保持する
- 未知画面やコース実行失敗を`needsAttention`へ移す
- ユーザー入力と定期観測が重なっても二つの操作を同時送信しない

### Appium session

- 実機上のWebDriverAgentを起動または再利用する
- 端末ごとに別のWDA・MJPEGポートを使う
- accessibility identifierまたは検証済みidentifier prefixで要素を検索する
- 要素IDを指定してタップする
- 観測時のセッション切断だけを一度再接続する
- 結果不明のタップを自動再送しない

### Course Engine

`CaptureCourseAdapter`は、選択されたJSONコースを共通の`CaptureAppAdapter`として実行します。

- blockerを先に探す
- 四つの画面証明のうち一つだけが成立することを確認する
- `running`または`paused`と現在画面に対応する遷移を一つ選ぶ
- 操作対象が一つだけ存在することを確認してタップする
- `stable`では何もせず、`needsOperator`では停止する

### App course

`apps/<app-name>/course.json`が次を所有します。

- bundle identifier
- `home`、`taskReady`、`recording`、`completionPending`を証明する要素
- `open-task`、`start-recording`、`stop-recording`、`discard-recording`などの操作
- 各操作がnavigation、録画開始、録画停止、削除、提出のどれか
- 目標状態と現在画面の組ごとの遷移
- ログイン、権限、警告を検出するblocker

MinuteとClaruはこの同じスキーマを使います。アプリ追加のためにDevice WorkerやAppium接続を複製しません。画面構造が現在の四状態で表せないアプリが現れたときだけ、実在する差分に基づいてCourse Engineを拡張します。

## 初期コースの状態遷移

```text
home
  ── open-task ──> taskReady
  ── start-recording ──> recording

recording
  ── 自然終了または stop-recording ──> completionPending

completionPending
  ── discard-recording ──> home
```

目標が`running`なら、discard後の`home`から次のチャンクを開始します。目標が`paused`なら、録画中は停止してdiscardし、`home`で待機します。コースの遷移を`needsOperator`へ変えれば、その画面ではタップせず停止します。

実際の状態は画面要素で確認し、時間だけから録画状態を推定しません。画面証明や操作対象が0件または複数件の場合も操作しません。

## エージェントの位置づけ

AIエージェントは制御ループの外側に置きます。アプリ更新後の画面要素を調べ、MinuteやClaruのコースを修正する支援には使えますが、通常運転中に未知の画面を推測してタップしません。

## 配布

開発中はSwift Packageの`field-app`実行ファイルを使用します。MinuteとClaruの実画面、二台同時運転、Wi-Fi切断復旧、8時間連続運転を確認した後、同じ実行器を署名・公証したMacアプリへ包みます。

MacアプリのDeveloper ID署名と、iPhone上のWebDriverAgentに必要なApple Development署名は別に管理します。端末UDID、Team ID、対象タスク、画面資料はリポジトリへ保存しません。
