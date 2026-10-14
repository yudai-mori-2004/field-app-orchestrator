# Field App Orchestrator

現場の作業者が頭に付けたiPhoneの撮影アプリを、Macから操作して撮影を続けるためのシステムです。対象は、一人称視点の動画を集めるアプリのMinute DataとClaru AIです。

どちらのアプリも、録画が一定の時間で区切られます。区切りのたびに、録画を保存または破棄し、タスクを選び、録画を始め直す必要があります。このシステムでは、この操作をMacが代わりに行います。撮影が始まってから作業者がするのは、休憩に入るときに止めて、戻ったときに再開することだけです。止めるのと再開するのは、iPhoneの背面をたたいて行います。

## 動き方

Macでは、iPhone 1台につき`field-app`というプログラムを1つ動かします。`field-app`は、iPhoneで動くWebDriverAgent（画面の部品を読んで押すためのアプリ）を通して、撮影アプリの画面を読み、ボタンを一つ押す、を繰り返します。

どのボタンを押すかは、撮影アプリごとの操作定義から決めます。操作定義は、アプリの画面の見分け方と、各画面でどのボタンを押すとどの画面へ移るかを書いたJSONです。`field-app`は、今の画面から目的の画面までの道順を毎回計算し、その最初の一歩だけを押します。作業者が画面を触って別の画面に移っても、次の一歩はその画面から決まります。

`field-app`が目指す状態は二つです。

- 撮影を続ける: 録画中であること。録画が区切られたら、保存または破棄して、次の録画を始める
- 止める: 録画していないこと。止めたあとは、次の指示が来るまで画面を読むだけなので、休憩中に作業者がiPhoneを使えます

Minute Dataで撮影を続けている間は、次の一周を繰り返します。

```text
録画中 → 30分で区切り → 上限のお知らせ（OK） → 完了画面 → 保存または破棄 → 録画待機 → カウントダウン → 録画中
```

どう進めればよいか判断できない画面（操作定義にない警告など）では、ボタンを押さずに止まり、人が画面を確かめるのを待ちます。

## 文書

はじめての方は、上から順に読むと全体がつかめます。

| 文書 | 内容 |
| --- | --- |
| [セットアップ](docs/setup.md) | MacとiPhoneを準備して、背面タップで録画が始まるまでの手順 |
| [運用](docs/operation.md) | 装着者に伝えること、Macが自分で立て直すこと、止まったときの対処、記録の読み方、iPhoneを足すとき |
| [仕組み](docs/architecture.md) | `field-app`がどう判断して操作しているか |
| [操作定義の形式](docs/app-operation-format.md) | 操作定義のJSONの書き方 |
| [確かめたこと](docs/status.md) | 実機で確かめたこと、まだ確かめていないこと、わかっている弱点 |
| [決定の記録](docs/decisions/) | 設計を決めたときの状況と理由 |
| [Minute Data](apps/minute-app/README.md)、[Claru AI](apps/claru-app/README.md) | アプリごとの操作定義と、実機でわかったアプリの動き |
| [Controller Core](mac/controller-core/README.md) | `field-app`のコードの部品の分担 |

## リポジトリの構成

```text
apps/
  minute-app/          Minute Dataの操作定義
  claru-app/           Claru AIの操作定義のひな形
mac/
  controller-core/     field-appのコードとテスト
docs/                  セットアップ、運用、仕組みの文書と、決定の記録
tools/                 WebDriverAgentの組み立て、サービスの登録、公開前の検査
config/local/          iPhoneごとの設定ファイルと操作定義を置く場所。Gitに入らない
```

## 開発

```sh
swift test --package-path mac/controller-core
swift build -c release --package-path mac/controller-core
python3 tools/check_public_tree.py
```

このリポジトリは公開しています。iPhoneのUDID、トークン、署名の情報、録画、画面のスクリーンショットは`config/local/`などのGitに入らない場所に置き、コミットする前に`tools/check_public_tree.py`で確かめます。エージェント向けの決まりは[AGENTS.md](AGENTS.md)にあります。

## いまの状態

Minute Data 1.29.0で、iPhone 12 mini 2台を、Wi-Fiだけでつないで同時に3時間撮影し続けることを確かめました。保存しながら続けて撮影すること、8時間続けて撮影すること、Claru AIの画面は、まだ確かめていません。詳しくは[確かめたこと](docs/status.md)にあります。
