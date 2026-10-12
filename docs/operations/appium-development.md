# Appium実機開発

通常運転では、一連の操作を書いた`xcodebuild test`ではなく、Appium XCUITest Driverが実機上のWebDriverAgentを維持します。Mac側のDevice Workerは、このHTTPセッションを通じて画面を観測し、必要な操作を一回ずつ送ります。

## 初回セットアップ

Node.js、Appium、XCUITest Driverの版はリポジトリで固定しています。

```sh
npm run setup:appium
npm run doctor:appium
```

`mise`がある場合は`.mise.toml`のNode.jsを自動的に使用します。Appiumのドライバー本体はリポジトリ内の`.appium/`へインストールされ、Gitには含まれません。

## サーバー起動

```sh
npm run appium
```

別のターミナルから、提出を行わないモックだけを対象に実機スモークテストを実行します。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
FAO_WDA_LOCAL_PORT=8100 \
npm run smoke:appium
```

端末IDと署名チームは実行時にだけ渡します。並列実行では、端末ごとに異なる`FAO_WDA_LOCAL_PORT`を割り当てます。MJPEG転送にはその値へ1000を加えたポートを使うため、指定できる範囲は1024から64535です。

スモークテストは、WebDriverAgentセッションを作成し、アクセシビリティ識別子でモックの開始と停止を操作してからセッションを閉じます。`useNewWDA=false`なので、次のセッションは実機上の既存WebDriverAgentを再利用できます。

## 現在の境界

このスモークテストは、署名、USB転送、WebDriverAgent、HTTP操作が成立することだけを確認します。8時間運転には、Device Workerとの接続、ヘルスチェック、セッション再作成、端末切断の分類、端末別ポート割り当て、構造化ログがさらに必要です。

Minute Dataをこのコマンドの対象にしません。実アプリの完全な操作は、[`0003-third-party-binary-validation.md`](../decisions/0003-third-party-binary-validation.md)で定めた公式検証環境だけで行います。
