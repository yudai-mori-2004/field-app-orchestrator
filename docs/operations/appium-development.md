# Appium実機開発

通常運転では、Appium XCUITest Driverが実機上のWebDriverAgentを維持します。一台分のDevice Workerは、このHTTPセッションから画面を観測し、対象アプリの操作定義に従って操作を一回ずつ送ります。

## 初回セットアップ

Node.js、Appium、XCUITest Driverの版はリポジトリで固定しています。

```sh
npm run setup:appium
npm run doctor:appium
```

`mise`がある場合は`.mise.toml`のNode.jsを自動的に使用します。Appiumのドライバー本体はリポジトリ内の`.appium/`へインストールされ、Gitには含まれません。

iPhoneでは、Macとの信頼、Developer Mode、対象アプリへのログイン、必要な権限許可を初回に済ませます。WebDriverAgentの署名に使うTeamへ端末を登録します。

## サーバー起動

```sh
npm run appium
```

Appiumサーバーは共通で一つ起動できます。端末ごとの`field-app`プロセスが、割り当てられたMinuteまたはClaruの操作定義を読み、別セッションを作ります。各端末には異なる`FAO_WDA_LOCAL_PORT`を割り当て、その1000番後に使うMJPEGポートも重複させません。

端末UDIDと署名Team IDは環境変数で実行時だけ渡し、設定ファイルやシェル履歴を公開リポジトリへ入れません。アプリごとの起動例は[`apps/minute-app/README.md`](../../apps/minute-app/README.md)と[`apps/claru-app/README.md`](../../apps/claru-app/README.md)にあります。

各`field-app`プロセスは`paused`で起動します。標準入力から次の命令を送ります。

- `start`: その端末を`running`（撮影を続ける）へ切り替える
- `pause`: `paused`（止める）へ切り替える。録画中なら停止し、`afterRecording`の方針で保存または破棄して、操作定義の止めた状態まで進める
- `status`: 目標状態、画面、ワーカーの状態を表示する
- `retry`: `needsAttention`の後、人が画面を確かめてから、新しい読み取りで再開する
- `quit`: 止めた状態まで進めてからセッションを閉じる。送信済みの操作があれば終わるのを待つ。`needsAttention`のときはタップせず、止めた状態を確かめられなかったことを表示して終了コード1で終わる。Ctrl-C、終了要求、ターミナルを閉じたときも同じ

`field-app`は、読み取った画面、押した操作、ワーカーの状態の変化を、時刻つきで標準出力に出します。

複数台では、一台につき一つの`field-app`プロセスを起動し、`FAO_DEVICE_ID`、`FAO_DEVICE_LABEL`、`FAO_WDA_LOCAL_PORT`を端末ごとに分けます。ユーザー入力はiPhoneへ直接タップせず、各ワーカーの目標状態だけを変更します。

## 長時間セッション

実機capabilityは次の方針です。

- `useNewWDA=false`で既存WebDriverAgentを再利用する。
- `noReset=true`でログイン状態とアプリデータを保つ。
- `forceAppLaunch=false`で、セッションを作り直しても対象アプリを起動し直さない。録画中に作り直しても撮影が途切れない。
- `shouldTerminateApp=false`でセッション終了時に対象アプリを強制終了しない。
- セッションを作った直後に`waitForIdleTimeout`を0にする。撮影アプリは常に画面を動かしているため、待つと1タップに20秒かかる。
- WDA起動と接続には明示的なタイムアウトと再試行回数を持たせる。
- 一台ごとにDerivedData、WDAポート、MJPEGポートを分ける。

観測用の要素検索がセッション切断で失敗した場合は、古いセッションを破棄し、新しいセッションを一度だけ作って再観測します。タップの応答が失われた場合は、端末側で操作が成立したか判定できないため自動再送せず、その端末を`needsAttention`へ移します。オペレーターが画面を確認して`retry`すると、新しい観測から再開します。タップの応答は返ったのに画面が変わらない場合は、アプリが取りこぼしたとみなし、新しい観測から道順を決め直します。

二台同時運転と8時間試験では、USB/Wi-Fi切断、WDA停止、対象アプリ停止を個別に発生させ、この境界で重複操作せず復旧できることを確認します。

## 実アプリの画面要素

Minuteの画面の部品は、Minute 1.29.0で確かめた値を`apps/minute-app/definition.example.json`に書いています。アプリの更新で部品が変わったら、この定義を直します。撮るタスクだけは、ローカルの操作定義で端末ごとに与えます。対象を一つに確認できなければタップしません。
