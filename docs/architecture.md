# アーキテクチャ

## 通常フロー

Mac上では、登録済みiPhoneごとに一つのDevice Workerと一つのAppiumセッションを起動します。各ワーカーは一台の端末と一つの販売先アプリだけを担当します。

```text
Controller
  ├─ Device Worker A ── minute-app ── Appium session A ── iPhone A
  ├─ Device Worker B ── minute-app ── Appium session B ── iPhone B
  └─ Device Worker C ── claru-app  ── Appium session C ── iPhone C
```

`claru-app`は将来追加する実装単位の例であり、現在のリポジトリにはMinute Dataの実装だけがあります。仕様が確定していないアプリの空パッケージは置きません。

ユーザーの開始・一時停止は、iPhoneへ直結したタップ命令ではなく、端末ごとの`running`または`paused`という目標状態です。Device Workerは、対象アプリのアダプターから現在画面と次の一操作を受け取り、最新の目標状態へ収束するまで直列に実行します。

## 責務

### Controller

- 登録端末とアプリ割り当ての読み込み
- 端末ごとのワーカープロセス起動・停止
- 状態、経過時間、再開回数、要対応状態の表示
- 全体または個別の開始・一時停止・再試行
- UI、CLI、物理入力から来た目標状態の統合

現段階では`minute-app` CLIを一台につき一プロセス起動します。複数端末を束ねるGUIはこの境界の上へ追加します。

### Device Worker

- 一台分の操作を直列化する
- 最新の目標状態だけを保持する
- 操作の影響を`navigation`、`startsRecording`、`stopsRecording`、`deletesRecording`、`submitsRecording`に分類する
- 未知画面やアダプター失敗を`needsAttention`へ移す
- ユーザー入力と定期観測が重なっても二つの操作を同時送信しない

### Appium session

- 実機上のWebDriverAgentを起動または再利用する
- 端末ごとに別のWDA・MJPEGポートを使う
- accessibility identifierまたは検証済みidentifier prefixで要素を検索する
- 要素IDを指定してタップする

### App implementation

`apps/<app-name>/`が次を所有します。

- bundle identifier
- 画面状態を証明する要素
- 操作対象と遷移条件
- 目標状態と現在画面から次の一操作を選ぶ規則
- 完了時にdiscard、保持、提出などを選ぶ最表層ポリシー
- 一意な要素を確認できない場合の停止

共通層へMinute固有の要素名や完了処理を入れません。新しい販売先アプリは、共通層を変更せず同じ粒度のパッケージとして追加します。

## Minute Dataの状態遷移

```text
home
  ── open-task ──> task-ready
  ── start-recording ──> recording

recording
  ── 30分自然終了または stop-recording ──> completion-pending

completion-pending
  ── discard-recording ──> home
```

目標が`running`なら、discard後の`home`から次のチャンクを開始します。目標が`paused`なら、録画中は停止してdiscardし、`home`で待機します。`requireOperator`ポリシーでは完了画面を操作せず`needsAttention`へ移ります。

実際の状態は画面要素で確認し、時間だけから録画状態を推定しません。ログイン、権限要求、警告、0件または複数件の操作対象、複数の画面証明が同時に見つかった状態では操作しません。

## エージェントの位置づけ

AIエージェントは制御ループの外側に置きます。診断情報からUI変更を調査し、アダプターを修正する支援には使えますが、通常運転中に未知の画面を推測してタップしません。

## 配布

開発中はSwift Packageの`minute-app`実行ファイルを使用します。実画面、二台同時運転、Wi-Fi切断復旧、8時間連続運転を確認した後、同じ実装を署名・公証したMacアプリへ包みます。

MacアプリのDeveloper ID署名と、iPhone上のWebDriverAgentに必要なApple Development署名は別に管理します。端末UDID、Team ID、対象タスク、画面資料はリポジトリへ保存しません。
