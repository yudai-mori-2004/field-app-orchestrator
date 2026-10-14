# セットアップ

Mac 1台とiPhoneを準備し、装着者（iPhoneを頭部に装着して作業する人）が背面をトリプルタップすると録画が開始される状態にするまでの手順です。iPhoneを2台以上使用する場合は、手順2〜7をiPhoneごとに繰り返します。

コマンドは、本リポジトリのディレクトリ（`git clone`で作成される`field-app-orchestrator`）で実行してください。

## 事前準備

| 項目 | 要件 |
| --- | --- |
| Mac | 使用するiPhoneのiOSに対応したXcodeが動作すること。Mac miniの場合はM1（2020年）以降。iPhone 1台あたり約150MBのメモリを使用する |
| iPhone | iOS 17以降で、MacのXcodeが対応しているiOSであること |
| Apple Developer Program | WebDriverAgentの署名に使用するTeamと、そのTeamに所属するApple Account |
| Wi-Fi | MacとiPhoneを同一ネットワークに接続でき、端末間の通信が許可されていること |
| 撮影アプリのアカウント | Minute Dataなど |

### 動作確認済みの構成

| 項目 | 構成 |
| --- | --- |
| Mac | MacBook Air（M1）、macOS 26.3、Xcode 26.4 |
| iPhone | iPhone 12 mini、iOS 26.4.1 / 26.5.2 |
| 撮影アプリ | Minute Data 1.29.0 |

### 補足

- Xcode 26.4.1はmacOS 26.2以降、Xcode 27はmacOS 26.6以降で動作します（[AppleのXcode対応表](https://developer.apple.com/support/xcode/)）。macOS 26の対応機種は、[macOS Tahoe 26に対応しているコンピュータ](https://support.apple.com/ja-jp/122867)を参照してください。
- iOS 17未満のiPhoneはアップデートが必要です。アップデートするとその時点の最新のiOSになるため、Macにも対応するXcodeが必要になります。
- ゲスト用Wi-Fiのように端末間の通信を遮断するネットワークでは、MacがiPhoneを検出できず、背面タップの指示もMacに届きません。持ち込みのルーターを使用すると、現場のネットワーク設定の影響を受けません。通信速度の要件はありません。

## 1. Macの準備

Macごとに1回だけ実施します。

1. Xcodeをインストールして起動し、iOSプラットフォームをインストールします。インストールが完了するまで、iOS向けのビルドはできません。
2. Xcodeの「Settings」で、Apple Developer ProgramのTeamに所属するApple Accountを追加します。
3. 本リポジトリをクローンします。

   ```sh
   git clone https://github.com/yudai-mori-2004/field-app-orchestrator.git
   cd field-app-orchestrator
   ```

4. 「システム設定」→「一般」→「共有」の「ローカルホスト名」を、役割名（`field-mac`など）に変更します。背面タップのショートカットは、このホスト名でMacに指示を送信します。すべての現場のMacに同じ名前を設定しておくと、iPhoneを別の現場で使用する場合やMacを交換する場合も、ショートカットを変更せずに使用できます。同一ネットワークにMacを2台設置する場合のみ、別の名前を設定します。
5. Macを電源に接続します。`field-app`の実行中は、Macはスリープしません。MacBookはふたを閉じるとスリープするため、開いたままにしてください。

## 2. iPhoneの準備

iPhoneごとに1回だけ実施します。画面の項目名は、iPhone 12 mini（iOS 26.4.1、日本語）のものです。

### 初期設定

工場出荷状態のiPhoneの電源を入れると、初期設定の画面が順に表示されます。以下の画面では、記載のとおりに選択してください。その他の画面での選択は、後から「設定」で変更できます。初期設定の画面の順序や項目名は、iOSのバージョンによって異なります。

1. 言語は「日本語」、国または地域は「日本」を選択します。iOSのアラートは、この言語の文言で識別します。
2. Wi-Fiは、Macと同じネットワークを選択します。
3. Face IDの画面では、「あとで“設定”でセットアップ」を選択します。
4. パスコードの作成画面では、「パスコードオプション」をタップし、「パスコードを使用しない」を選択します。パスコードを設定すると、画面がロックされたときにMacから解除できません。
5. iOSのアップデートを勧める画面では、「あとでアップデート」を選択します。iOS 17未満の場合のみアップデートします。
6. Apple Accountの画面では、撮影アプリのインストールに使用するApple Accountでサインインします。

### 設定アプリでの変更

1. 「一般」→「情報」→「名前」で、他のiPhoneと重複しない名前（`minute-01`など）に変更します。Macの一覧でiPhoneを識別するために使用します。
2. 「一般」→「ソフトウェアアップデート」→「自動アップデート」で、「iOSアップデート」の「自動インストール」をオフにします。MacのXcodeが対応していないiOSにアップデートされると、操作できなくなります。
3. 「画面表示と明るさ」→「自動ロック」で、「なし」を選択します。ロックされると撮影アプリがバックグラウンドに移り、録画が停止します。
4. 「Face IDとパスコード」で、パスコードがオフになっていることを確認します。オフの場合は「パスコードをオンにする」が表示されます。「パスコードをオフにする」が表示されている場合は、それをタップします。

### Macとの接続

1. iPhoneをUSBケーブルでMacに接続します。
2. iPhoneに「このコンピュータを信頼しますか?」と表示されたら、「信頼」を選択します。
3. iPhoneの「設定」→「プライバシーとセキュリティ」→「デベロッパモード」をオンにします。再起動を求められるので、再起動します。
4. 再起動後に「デベロッパモードをオンにしますか?」と表示されたら、「オンにする」を選択します。
5. Macで次のコマンドを実行し、iPhoneのUDIDを確認します。iPhoneの名前の行の、末尾の括弧内がUDIDです。

   ```sh
   xcrun xctrace list devices
   ```

USBケーブルは、手順4のWebDriverAgentのビルドが完了するまで接続したままにします。

### 撮影アプリの準備

1. 撮影アプリをインストールして起動し、ログインします。
2. 撮影するタスクを開き、手動で録画を開始します。カメラやマイクへのアクセス許可を求められたら、許可します。許可がない状態で`field-app`を実行すると、撮影アプリがアクセス許可を求める画面を表示した時点で、`field-app`が停止します。
3. 録画を停止し、テスト用の録画を破棄します。
4. Minute Dataでは、表示言語が英語であることを確認します。英語以外の場合は、Minute Dataの設定で英語に変更します。操作定義は、英語表示の文言で画面を識別します。

## 3. 設定ファイルの作成

iPhoneごとに`config/local/<名前>.env`を作成します。`config/local/`はGit管理外のため、UDIDやトークンを記載して問題ありません。

```sh
FAO_DEVICE_ID=<iPhoneのUDID>
FAO_DEVICE_LABEL=minute-01
FAO_CONTROL_PORT=8400
FAO_CONTROL_TOKEN=<トークン>
FAO_DEVELOPMENT_TEAM=<Team ID>
```

| 変数 | 説明 |
| --- | --- |
| `FAO_DEVICE_ID` | iPhoneのUDID |
| `FAO_DEVICE_LABEL` | `field-app`の識別名。サービス名とログファイル名に使用される。英数字、`.`、`_`、`-`のみ使用できる |
| `FAO_CONTROL_PORT` | 背面タップの指示を受信するポート番号。iPhoneごとに異なる値を設定する（8400、8401、…） |
| `FAO_CONTROL_TOKEN` | 背面タップの指示の認証に使用するトークン。16文字以上。`openssl rand -hex 16`で生成できる |
| `FAO_DEVELOPMENT_TEAM` | WebDriverAgentの署名に使用するTeam ID。Apple Developerサイトの「メンバーシップの詳細」に記載されている10文字の英数字 |
| `FAO_BATTERY_STOP_PERCENT` | 任意。撮影を停止するバッテリー残量（1〜50）。省略時は10 |
| `FAO_WDA_XCTESTRUN` | 任意。WebDriverAgentのビルド成果物のパス。省略時は`.wda/`内のもの |

## 4. WebDriverAgentのビルド

WebDriverAgentは、iPhoneのUI要素の取得とタップを行うアプリです。固定のバージョンをnpmレジストリから取得し、チェックサムを確認してからビルドします。ビルド時に、iPhoneがTeamに登録されます。

```sh
set -a && . config/local/minute-01.env && set +a && tools/setup_wda.sh "$FAO_DEVICE_ID"
```

最後に`** TEST BUILD SUCCEEDED **`と表示されれば完了です。ビルド成果物は`.wda/`に出力され、すべてのiPhoneで共通に使用します。完了したら、USBケーブルを外します。以降は、iPhoneがMacと同じWi-Fiに接続されていれば操作できます。

ビルドは`.wda/`を再作成するため、稼働中の`field-app`のサービスがある場合は、事前に登録を解除してください（[iPhoneの追加](operation.md#iphoneの追加)）。署名の有効期限は1年です。期限が切れる前に再ビルドしてください。

## 5. 操作定義の作成

撮影アプリの操作定義のサンプルをコピーし、撮影するタスクの名前を設定します。次の例では、Minute DataのタスクFood Prepを設定しています。タスク名は、撮影アプリのタスク一覧に表示されているとおりに記載してください。

```sh
mkdir -p config/local
sed 's/REPLACE_WITH_TASK_TITLE/Food Prep/g' apps/minute-app/definition.example.json > config/local/minute.json
swift run --package-path mac/controller-core field-app --validate-definition config/local/minute.json
```

`Valid definition`と表示されれば使用できます。検証では、未設定の値がないことと、すべての画面から撮影継続と停止の両方の状態に到達できることを確認します。同じタスクを撮影するiPhoneでは、同じ操作定義を使用できます。

サンプルは、録画が区切られるたびに破棄する設定（`"afterRecording": "discard"`）です。試験運用中はこの設定のまま使用し、録画を提出する本番運用で`save`に変更します（[保存モードへの切り替え](operation.md#保存モードへの切り替え)）。

## 6. サービスの登録

`field-app`を、macOSのlaunchdのサービスとして登録します。Macへのログイン時に起動し、異常終了した場合は自動的に再起動されます。

```sh
tools/service.sh install config/local/minute-01.env config/local/minute.json
```

最後に`Started dev.fieldapporchestrator.field-app.minute-01.`と表示されれば登録完了です。`field-app`のログは`~/Library/Logs/field-app/minute-01.log`に出力されます。

```sh
tail -f ~/Library/Logs/field-app/minute-01.log
```

初回は、WebDriverAgentの起動に40秒ほどかかる場合があります。その後`screen`で始まる行が出力されれば、`field-app`がiPhoneの画面を読み取れています。登録後、最初の指示を受信するまでは、画面の読み取りだけを行います。

## 7. 背面タップの設定

### ショートカットの作成

iPhoneで、開始用と終了用のショートカットを1つずつ作成し、背面タップに割り当てます。

1. 「ショートカット」アプリで新規ショートカットを作成し、名前を「開始」にします。
2. 「サウンドを再生」アクションを追加します。設定は不要です。タップの認識を知らせる効果音になります。
3. 「URLの内容を取得」アクションを追加し、URLに`http://field-mac.local:8400/start?token=<トークン>`を設定します。`field-mac`は手順1で設定したMacのローカルホスト名、ポート番号とトークンはこのiPhoneの設定ファイルの値です。
4. 同じ「URLの内容を取得」アクションの詳細を開き、「方法」を`POST`に変更します。初期値は`GET`で、`GET`のままでは`field-app`が指示を受け付けません。
5. 「テキストを読み上げる」アクションを追加し、読み上げる内容に「URLの内容」を設定します。
6. 同様に「終了」のショートカットを作成します。手順3のURLの`/start`を`/pause`に変更します。
7. 「開始」と「終了」を、ショートカットアプリ内で1回ずつ実行します。「“開始”が“field-mac.local”に接続することを許可しますか?」と表示されたら、「常に許可」を選択します。Mac側で`field-app`への接続を許可するか確認された場合も、許可します。
8. 「設定」→「アクセシビリティ」→「タッチ」→「背面タップ」で、「トリプルタップ」に「開始」、「ダブルタップ」に「終了」を割り当てます。

### 動作確認

1. iPhoneの背面をトリプルタップします。効果音に続いて「撮影を開始します。」と読み上げられ、20秒ほどで録画が開始されます。
2. iPhoneの背面をダブルタップします。効果音に続いて「撮影を終了します。」と読み上げられ、10秒ほどで録画が停止します。

効果音の後に音声が続かない場合は、[音声応答がないとき](operation.md#音声応答がないとき)を参照してください。

以上でセットアップは完了です。運用については[運用](operation.md)を参照してください。
