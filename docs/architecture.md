# アーキテクチャ

## 通常フロー

Mac上のコントローラーは、登録済みiPhoneごとに一つのワーカーを起動します。ワーカーは対象端末のUDIDと割り当てられたアプリ・作業だけを受け取り、他端末と状態を共有せずに進みます。

```text
Mac Controller
  ├─ Device Worker A ── App Adapter ── iPhone A
  ├─ Device Worker B ── App Adapter ── iPhone B
  └─ Device Worker C ── App Adapter ── iPhone C
```

通常運転では、ワーカーはAppium XCUITest Driverが維持するWebDriverAgentセッションからアクセシビリティ要素を観測し、現在状態に許された操作だけを実行します。既存のXCUITestテストケースはアダプターの検証に使います。正常遷移を確認できなければ、その端末の処理を止め、診断情報を保存します。他端末の実行は継続できます。

ユーザーの開始・一時停止操作はiPhoneへのタップ命令ではなく、端末ごとの目標状態としてControllerへ入ります。各Device Workerは最新の目標状態だけを見て操作を直列化します。

## 責務

### Controller

- 登録端末と割り当ての読み込み
- UDIDごとのワーカープロセス起動・停止
- 状態一覧、経過時間、再開回数、要対応状態の表示
- オペレーターによる全体開始、個別の開始・一時停止、再試行
- UI、CLI、物理ボタンから来た目標状態の統合

### Device worker

- 一台のiPhoneとの接続維持
- WebDriverAgentセッションとタイムアウトの管理
- 最新の目標状態へ収束する操作の直列実行
- 切断、ランナー失敗、アプリ異常終了の分類
- 構造化ログと診断成果物の保存

### App adapter

- 対象アプリのbundle identifier
- 既知の画面状態と、それを証明する要素
- 各状態から許される操作
- 操作後に成立すべき状態

Minute Data以外のアプリを追加するときは、新しいアダプターを追加します。共通ワーカーへアプリ固有の要素名や待機時間を埋め込みません。

## 状態遷移

最初の実装では、次の状態だけを扱います。

```text
disconnected
  → connecting
  → ready
  → launching_app
  → observing
  → performing_known_action
  → observing

どの状態からでも:
  → needs_attention
  → stopped
```

通常運転の目標状態は`running`と`paused`です。録画中に自然終了してホームへ戻り、目標状態が`running`なら次のチャンクを開始します。`paused`なら操作せず待機します。

実際に録画中かどうか、30分終了後にどの画面へ戻るかはアクセシビリティ要素で確認します。時間だけで録画状態を推定しません。詳細は[`0002-external-capture-intent.md`](decisions/0002-external-capture-intent.md)に記録します。

## エージェントの位置づけ

AIエージェントは制御ループの外側に置きます。診断成果物からUI変更を調査したり、アダプターの修正案を作ることはできますが、承認されていない操作を実機へ送る権限は持ちません。

## 配布

開発中はリポジトリからXCUITestを実行します。通常フローと復旧条件を確認した後、Macコントローラーを署名・公証した`.app`と`.dmg`として配布します。

MacアプリのDeveloper ID署名と、iPhone上で動くテストランナーのApple Development署名は別に管理します。アプリのパッケージ化によって、iPhoneの登録やテストランナーのプロビジョニングが不要になるわけではありません。
