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

- `start`: その端末を`running`へ切り替える
- `pause`: 録画中なら停止し、操作定義で指定された完了処理を通って`paused`へ収束させる
- `status`: 目標状態、観測画面、ワーカー状態を表示する
- `retry`: `needsAttention`を確認した後、現在画面の再観測から再開する
- `quit`: `paused`へ収束させてからセッションを閉じる。送信済みの操作があれば終わるのを待つ。`needsAttention`のときはタップせず、一時停止を確認できなかったことを表示して終了コード1で終わる

複数台では、一台につき一つの`field-app`プロセスを起動し、`FAO_DEVICE_ID`、`FAO_DEVICE_LABEL`、`FAO_WDA_LOCAL_PORT`を端末ごとに分けます。ユーザー入力はiPhoneへ直接タップせず、各ワーカーの目標状態だけを変更します。

## 長時間セッション

実機capabilityは次の方針です。

- `useNewWDA=false`で既存WebDriverAgentを再利用する。
- `noReset=true`でログイン状態とアプリデータを保つ。
- `shouldTerminateApp=false`でセッション終了時に対象アプリを強制終了しない。
- WDA起動と接続には明示的なタイムアウトと再試行回数を持たせる。
- 一台ごとにDerivedData、WDAポート、MJPEGポートを分ける。

観測用の要素検索がセッション切断で失敗した場合は、古いセッションを破棄し、新しいセッションを一度だけ作って再観測します。タップの応答が失われた場合は、端末側で操作が成立したか判定できないため自動再送せず、その端末を`needsAttention`へ移します。オペレーターが画面を確認して`retry`すると、新しい観測から再開します。

二台同時運転と8時間試験では、USB/Wi-Fi切断、WDA停止、対象アプリ停止を個別に発生させ、この境界で重複操作せず復旧できることを確認します。

## 実アプリの画面要素

アクセシビリティ識別子はアプリ版ごとにローカルの操作定義で確定します。対象を一意に確認できなければタップしません。
