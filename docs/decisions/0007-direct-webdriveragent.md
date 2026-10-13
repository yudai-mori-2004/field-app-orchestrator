# 0007: Appiumを外し、field-appがWebDriverAgentと直接話す

## 状況

iPhoneは作業者の頭に付くので、現場ではMacとケーブルでつなげません。それまでの実機の確認は、すべてUSBでつないだ状態でした。

ケーブルを抜いて確かめると、iPhoneとWebDriverAgentは無線で成り立っていました。Xcodeは`devicectl`でiPhoneとの経路を保ち、`xcodebuild`でWebDriverAgentを5〜10秒で起動できます。WebDriverAgentは、Wi-FiでもXcodeの経路でも、Macからの問い合わせにすぐ答えます。

止まったのはAppiumでした。Appium（XCUITest Driver 12.17.2）は、iPhoneを探すとき、iOSの版を調べるとき、WebDriverAgentを起動する前にアプリを片づけるときに、USBでつながった端末だけを扱う仕組みを使います。ケーブルのないiPhoneは見つからず、WebDriverAgentを起動し直すこともできませんでした。Appiumの新しい無線用のトンネルも、iPhoneについてはUSBの端末しか扱っていません。

## 決定

Appiumを外します。`field-app`は、iPhone上のWebDriverAgentとネットワーク越しに直接話します。

- iPhoneの宛先は、XcodeがiPhoneへ保つ経路のアドレスで、`devicectl`で調べる
- WebDriverAgentが返事をしないときは、iPhoneに届くことを確かめてから、`field-app`が`xcodebuild`で起動し直す。iPhoneに届かない間は待つ。3回起動しても返事がなければ人を待つ
- WebDriverAgentは`field-app`を終えても動き続け、次の`field-app`が使い回す
- WebDriverAgentは`tools/setup_wda.sh`で一度だけ組み立てる。版と照合値はスクリプトで固定する

## 結果

- 現場で動かすものは、iPhone 1台につき`field-app`と`xcodebuild`の1組になる。Appiumのサーバーと、そのためのNode.jsは要らない
- Wi-FiでもUSBでも同じ仕組みで動き、どのiPhoneも同じポートで済み、IPアドレスを固定しなくてよい
- WebDriverAgentの版を上げるときは、スクリプトの版と照合値を書き換えて組み立て直す
- Appiumの`mobile:`コマンドで送っていた操作は、`field-app`がWebDriverAgentの入口（`/wda/...`）へ直接送る
