# セットアップ

Mac 1台とiPhoneを準備して、装着者（iPhoneを頭に付けて作業する人）が背面を3回たたくと録画が始まるところまでの手順です。iPhoneを2台以上使うときは、2から7をiPhoneごとに繰り返します。

コマンドは、このリポジトリのフォルダー（`git clone`で作った`field-app-orchestrator`）で実行します。

## 用意するもの

- **Mac**: iPhoneのiOSに対応するXcodeが動くMac。確かめた組み合わせは、MacBook Air（M1）、macOS 26.3、Xcode 26.4です。Xcode 26.4.1はmacOS 26.2以降で、Xcode 27はmacOS 26.6以降で動きます（[AppleのXcodeの対応表](https://developer.apple.com/support/xcode/)）。macOS 26が入るMac miniは、M1（2020年）以降です（[macOS Tahoe 26に対応しているコンピュータ](https://support.apple.com/ja-jp/122867)）。iPhone 1台につき、Macのメモリを約150MB使います。
- **iPhone**: iOS 17以降で、MacのXcodeが対応しているiOSのもの。確かめたのは、iPhone 12 miniのiOS 26.4.1と26.5.2です。iOS 17より前のiPhoneはアップデートが要り、アップデートするとそのときの最新のiOSになります。その場合は、Macにもそれに対応するXcodeを入れます。
- **Apple Developer ProgramのTeam**: iPhoneで動かすWebDriverAgentの署名に使います。そのTeamに入っているApple Accountも要ります。
- **Wi-Fi**: MacとiPhoneが同じネットワークにいて、端末どうしが通信できるもの。MacはWi-FiでiPhoneを見つけ、iPhoneは背面タップの指示をWi-FiでMacに送ります。ゲスト用のWi-Fiのように端末どうしの通信を止めるネットワークでは、どちらも届きません。持ち込みの小さなルーターを使えば、現場のネットワークの設定に左右されません。回線の速さは問いません。
- **撮影アプリのアカウント**: Minute Dataなど。

## 1. Macを準備する

Macごとに一度だけ行います。

1. Xcodeを入れて一度開き、iOSのプラットフォームを入れます。入れ終わるまで、iPhone向けの組み立てはできません。
2. Xcodeの「Settings」で、Apple DeveloperのTeamに入っているApple Accountを追加します。
3. このリポジトリを取得します。

   ```sh
   git clone https://github.com/yudai-mori-2004/field-app-orchestrator.git
   cd field-app-orchestrator
   ```

4. 「システム設定」→「一般」→「共有」の下にある「ローカルホスト名」を、役割の名前（`field-mac`など）にします。背面タップのショートカットは、この名前でMacに指示を送ります。どの現場のMacにも同じ名前を付けておけば、iPhoneを別の現場に持っていっても、Macを替えても、ショートカットを作り直さずに済みます。1つのネットワークにMacを2台置くときだけ、名前を分けます。
5. Macを電源につなぎます。`field-app`は、動いている間Macをスリープさせません。MacBookはふたを閉じるとスリープするので、開けたままにします。

## 2. iPhoneを準備する

iPhoneごとに一度だけ行います。項目の名前は、iPhone 12 mini（iOS 26.4.1、日本語）のものです。

### 初期設定の画面

工場出荷状態のiPhoneの電源を入れると、初期設定の画面が順に出ます。次の画面では、書いてあるとおりに選びます。ほかの画面で選んだものは、あとから「設定」で変えられます。初期設定の画面の順番や名前は、iPhoneに入っているiOSの版によって変わります。

1. 言語は「日本語」を、国または地域は「日本」を選びます。iOSの警告は、この言語の文で見分けます。
2. Wi-Fiは、Macと同じネットワークを選びます。
3. Face IDの画面では、「あとで“設定”でセットアップ」を選びます。
4. パスコードを作る画面では、「パスコードオプション」を押し、「パスコードを使用しない」を選びます。パスコードがあると、画面がロックされたときにMacから解除できません。
5. iOSのアップデートを勧める画面では、「あとでアップデート」を選びます。入っているiOSが17より前のときだけ、アップデートします。
6. Apple Accountの画面では、撮影アプリを入れるのに使うApple Accountでサインインします。

### 「設定」アプリ

1. 「一般」→「情報」→「名前」を開き、ほかのiPhoneと重ならない名前（`minute-01`など）にします。Macの一覧でiPhoneを見分けるのに使います。
2. 「一般」→「ソフトウェアアップデート」→「自動アップデート」を開き、「iOSアップデート」の「自動インストール」をオフにします。MacのXcodeが対応していないiOSに上がると、操作できなくなります。
3. 「画面表示と明るさ」→「自動ロック」を開き、「なし」を選びます。ロックされると、撮影アプリが背後に回って録画が止まります。
4. 「Face IDとパスコード」を開き、パスコードがオフになっていることを確かめます。オフなら「パスコードをオンにする」が出ています。「パスコードをオフにする」が出ているときは、それを押します。

### Macにつなぐ

1. iPhoneをUSBケーブルでMacにつなぎます。
2. iPhoneに「このコンピュータを信頼しますか?」と出たら、「信頼」を選びます。
3. iPhoneの「設定」→「プライバシーとセキュリティ」→「デベロッパモード」を開き、オンにします。再起動を求められるので、再起動します。
4. 再起動のあとに「デベロッパモードをオンにしますか?」と出たら、「オンにする」を選びます。
5. Macで次を実行し、iPhoneのUDIDを調べます。iPhoneの名前の行の、最後のかっこの中がUDIDです。

   ```sh
   xcrun xctrace list devices
   ```

USBケーブルは、4でWebDriverAgentを組み立て終わるまで、つないだままにします。

### 撮影アプリ

1. 撮影アプリを入れて開き、ログインします。
2. 撮るタスクを開き、録画を一度手で始めます。カメラやマイクの許可を求められたら、許可します。許可がないまま`field-app`で動かすと、撮影アプリが許可を求める画面を出したところで、`field-app`が止まります。
3. 録画を止め、試しの録画を破棄します。
4. Minute Dataでは、表示が英語であることを確かめます。英語でないときは、Minute Dataの設定で英語にします。操作定義は、英語の表示の文で画面を見分けます。

## 3. 設定ファイルを作る

iPhoneごとに、`config/local/<名前>.env`を作ります。`config/local/`はGitに入らないので、UDIDやトークンをそのまま書いて構いません。

```sh
FAO_DEVICE_ID=<iPhoneのUDID>
FAO_DEVICE_LABEL=minute-01
FAO_CONTROL_PORT=8400
FAO_CONTROL_TOKEN=<トークン>
FAO_DEVELOPMENT_TEAM=<Team ID>
```

| 変数 | 内容 |
| --- | --- |
| `FAO_DEVICE_ID` | iPhoneのUDID |
| `FAO_DEVICE_LABEL` | `field-app`の名前。サービスの名前と記録のファイル名になる。英数字と`.`、`_`、`-`で付ける |
| `FAO_CONTROL_PORT` | 背面タップの指示を受けるポート。iPhoneごとに変える（8400、8401、…） |
| `FAO_CONTROL_TOKEN` | 背面タップの指示に付ける合言葉。16文字以上。`openssl rand -hex 16`で作れる |
| `FAO_DEVELOPMENT_TEAM` | WebDriverAgentを署名するTeamのID。Apple Developerのサイトの「メンバーシップの詳細」に出ている10文字 |
| `FAO_BATTERY_STOP_PERCENT` | 省略できる。撮影を止める電池の残量（1〜50）。省略すると10 |
| `FAO_WDA_XCTESTRUN` | 省略できる。WebDriverAgentの組み立て結果の場所。省略すると`.wda/`のもの |

## 4. WebDriverAgentを組み立てる

WebDriverAgentは、iPhoneの画面の部品を読んで押すためのアプリです。決まった版をnpmの登録所から取得し、照合値を確かめてから組み立てます。組み立てるとき、iPhoneがTeamに登録されます。

```sh
set -a && . config/local/minute-01.env && set +a && tools/setup_wda.sh "$FAO_DEVICE_ID"
```

最後に`** TEST BUILD SUCCEEDED **`と出れば終わりです。組み立てた結果は`.wda/`に入り、すべてのiPhoneで共通に使います。終わったら、USBケーブルを抜きます。これからは、iPhoneがMacと同じWi-Fiにいれば操作できます。

組み立ては`.wda/`を作り直すので、すでに動いている`field-app`のサービスがあれば、先に外します（[運用](operation.md#iphoneを足す)）。署名は1年で切れるので、切れる前にもう一度組み立てます。

## 5. 操作定義を用意する

撮影アプリの操作定義の例をコピーし、撮るタスクの名前を入れます。次の例では、Minute DataのタスクFood Prepにしています。タスクの名前は、撮影アプリのタスク一覧に出ているとおりに書きます。

```sh
mkdir -p config/local
sed 's/REPLACE_WITH_TASK_TITLE/Food Prep/g' apps/minute-app/definition.example.json > config/local/minute.json
swift run --package-path mac/controller-core field-app --validate-definition config/local/minute.json
```

`Valid definition`と出れば使えます。検証では、値の入れ忘れがないことと、どの画面からも「撮影を続ける」と「止める」の両方に行き着けることを確かめます。同じタスクを撮るiPhoneは、同じ操作定義を使えます。

例では、録画が区切られるたびに破棄する設定（`"afterRecording": "discard"`）になっています。試すあいだはこのまま使い、録画を提出する本番で`save`に変えます（[運用](operation.md#保存に切り替える)）。

## 6. サービスとして登録する

`field-app`を、macOSのlaunchdのサービスとして登録します。Macにログインすると起動し、落ちたときは自動で起動し直されます。

```sh
tools/service.sh install config/local/minute-01.env config/local/minute.json
```

最後に`Started dev.fieldapporchestrator.field-app.minute-01.`と出れば登録できています。`field-app`の記録は、`~/Library/Logs/field-app/minute-01.log`に出ます。

```sh
tail -f ~/Library/Logs/field-app/minute-01.log
```

最初は、WebDriverAgentの起動に40秒ほどかかることがあります。そのあと`screen`で始まる行が出れば、`field-app`がiPhoneの画面を読めています。登録したあと、最初の指示が来るまでは、画面を読むだけです。

## 7. 背面タップを設定する

### ショートカットを作る

iPhoneで、開始と終了のショートカットを1つずつ作り、背面タップに割り当てます。

1. 「ショートカット」アプリで新しいショートカットを作り、名前を「開始」にします。
2. 「サウンドを再生」を追加します。何も設定しません。たたいたことが伝わった合図の効果音になります。
3. 「URLの内容を取得」を追加し、URLを`http://field-mac.local:8400/start?token=<トークン>`にします。`field-mac`は1で付けたMacのローカルホスト名、ポートとトークンはこのiPhoneの設定ファイルのものです。
4. 同じ「URLの内容を取得」の項目を開き、「方法」を`POST`にします。初めは`GET`になっていて、`GET`のままでは`field-app`が指示を受け付けません。
5. 「テキストを読み上げる」を追加し、読み上げる内容を「URLの内容」にします。
6. 同じように「終了」のショートカットを作ります。3のURLの`/start`を`/pause`にします。
7. 「開始」と「終了」を、ショートカットアプリの中で1回ずつタップして動かします。「“開始”が“field-mac.local”に接続することを許可しますか?」と聞かれたら、「常に許可」を選びます。Macが`field-app`への接続を許可するかを聞いたときも、許可します。
8. 「設定」→「アクセシビリティ」→「タッチ」→「背面タップ」で、「トリプルタップ」に「開始」を、「ダブルタップ」に「終了」を選びます。

### 動きを確かめる

1. iPhoneの背面を3回たたきます。効果音に続いて「撮影を開始します。」と聞こえ、20秒ほどで録画が始まります。
2. iPhoneの背面を2回たたきます。効果音に続いて「撮影を終了します。」と聞こえ、10秒ほどで録画が止まります。

効果音のあとに声が続かないときは、[声が聞こえないとき](operation.md#声が聞こえないとき)を見ます。

ここまでで準備は終わりです。動かし始めてからのことは、[運用](operation.md)にあります。
