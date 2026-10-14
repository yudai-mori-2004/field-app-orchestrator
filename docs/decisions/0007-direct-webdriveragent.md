# 0007: Appiumを廃止し、field-appがWebDriverAgentと直接通信する

## 状況

iPhoneは作業者の頭部に装着するため、現場ではMacとケーブルで接続できません。それまでの実機での確認は、すべてUSB接続の状態で行っていました。

ケーブルを外して確認したところ、iPhoneとWebDriverAgentは無線接続で動作していました。Xcodeは`devicectl`でiPhoneとの経路を維持し、`xcodebuild`でWebDriverAgentを5〜10秒で起動できます。WebDriverAgentは、Wi-Fi経由でもXcodeの経路経由でも、Macからのリクエストに即座に応答します。

停止していたのはAppiumでした。Appium（XCUITest Driver 12.17.2）は、iPhoneの検出、iOSのバージョンの取得、WebDriverAgent起動前のアプリの終了処理で、USB接続の端末のみを扱う仕組みを使用しています。ケーブル未接続のiPhoneは検出されず、WebDriverAgentの再起動もできませんでした。Appiumの新しい無線接続用のトンネルも、iPhoneについてはUSB接続の端末のみに対応しています。

## 決定

Appiumを廃止します。`field-app`は、iPhone上のWebDriverAgentとネットワーク経由で直接通信します。

- iPhoneの接続先は、XcodeがiPhoneとの間に維持している経路のアドレスを`devicectl`で取得して使用する
- WebDriverAgentが応答しない場合は、iPhoneに到達できることを確認してから、`field-app`が`xcodebuild`で再起動する。iPhoneに到達できない間は待機する。3回起動しても応答がなければ要対応状態になる
- WebDriverAgentは`field-app`の終了後も動作を継続し、次に起動した`field-app`が再利用する
- WebDriverAgentは`tools/setup_wda.sh`でビルドする。バージョンとチェックサムはスクリプト内で固定する

## 結果

- 現場で実行するのは、iPhone 1台につき`field-app`と`xcodebuild`の1組になる。Appiumサーバーと、そのためのNode.jsは不要になる
- Wi-FiでもUSBでも同じ仕組みで動作し、すべてのiPhoneで同じポートを使用でき、IPアドレスを固定する必要がない
- WebDriverAgentのバージョンを上げる場合は、スクリプトのバージョンとチェックサムを書き換えて再ビルドする
- Appiumの`mobile:`コマンドで送信していた操作は、`field-app`がWebDriverAgentのエンドポイント（`/wda/...`）に直接送信する
