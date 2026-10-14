# Field App Orchestrator

現場作業者が頭部に装着したiPhoneの撮影アプリを、Macから自動操作して撮影を継続するためのシステムです。対象アプリは、一人称視点の動画を収集するMinute DataとClaru AIです。

どちらのアプリも、録画は一定時間ごとに区切られます。区切りごとに、録画の保存または破棄、タスクの選択、録画の再開始が必要です。本システムでは、これらの操作をMacが代行します。撮影開始後に作業者が行うのは、休憩時の撮影停止と、休憩後の撮影再開だけです。いずれもiPhoneの背面タップで行います。

## 動作の概要

Macでは、iPhone 1台につき1つの`field-app`プロセスを実行します。`field-app`は、iPhone上で動作するWebDriverAgent（UI要素の取得とタップを行うアプリ）を介して撮影アプリの画面を読み取り、ボタンを1つタップする処理を繰り返します。

タップするボタンは、撮影アプリごとの操作定義に基づいて決定します。操作定義は、画面の識別条件と、各画面でどのボタンをタップするとどの画面に遷移するかを記述したJSONです。`field-app`は、現在の画面から目標の画面までの経路を毎回計算し、その最初の操作だけを実行します。作業者が画面に触れて別の画面に遷移した場合も、次の操作は遷移後の画面から決定します。

目標状態は次の2つです。

- 撮影継続（`running`）: 録画中の状態。録画が区切られると、保存または破棄を行い、次の録画を開始する
- 停止（`paused`）: 録画していない状態。停止後は次の指示を受けるまで画面の読み取りだけを行うため、休憩中に作業者がiPhoneを使用できる

Minute Dataで撮影を継続している間は、次のサイクルを繰り返します。

```text
録画中 → 30分で区切り → 上限到達ダイアログ（OK） → 録画完了画面 → 保存または破棄 → 録画待機 → カウントダウン → 録画中
```

処理を判断できない画面（未定義のiOSアラートなど）では、タップを行わずに停止し、担当者の確認を待ちます。

## ドキュメント

初めての方は、上から順に読むと全体像を把握できます。

| ドキュメント | 内容 |
| --- | --- |
| [セットアップ](docs/setup.md) | MacとiPhoneの準備から、背面タップで録画を開始できるまでの手順 |
| [運用](docs/operation.md) | 装着者への説明、自動復旧、停止時の対応、ログの見方、iPhoneの追加とMacの交換 |
| [アーキテクチャ](docs/architecture.md) | `field-app`の判断と操作の仕組み |
| [操作定義の形式](docs/app-operation-format.md) | 操作定義のJSONの書式 |
| [動作確認状況](docs/status.md) | 動作確認済みの項目、未確認事項、既知の問題 |
| [設計判断の記録](docs/decisions/) | 設計を決定した経緯と理由 |
| [Minute Data](apps/minute-app/README.md)、[Claru AI](apps/claru-app/README.md) | アプリごとの操作定義と、実機で確認したアプリの挙動 |
| [Controller Core](mac/controller-core/README.md) | `field-app`のコード構成 |

## リポジトリ構成

```text
apps/
  minute-app/          Minute Dataの操作定義
  claru-app/           Claru AIの操作定義（テンプレート）
mac/
  controller-core/     field-appのソースコードとテスト
docs/                  セットアップ、運用、アーキテクチャのドキュメントと設計判断の記録
tools/                 WebDriverAgentのビルド、サービスの登録、公開前チェックのスクリプト
config/local/          iPhoneごとの設定ファイルと操作定義の配置先（Git管理外）
```

## 開発

```sh
swift test --package-path mac/controller-core
swift build -c release --package-path mac/controller-core
python3 tools/check_public_tree.py
```

本リポジトリは公開リポジトリです。iPhoneのUDID、トークン、署名情報、録画データ、実機画面のスクリーンショットは、`config/local/`などGit管理外の場所に保存してください。コミット前に`tools/check_public_tree.py`を実行し、これらが含まれていないことを確認します。エージェント向けの規約は[AGENTS.md](AGENTS.md)を参照してください。

## 開発状況

Minute Data 1.29.0で、iPhone 12 mini 2台をWi-Fiのみで接続し、3時間の同時連続撮影を確認済みです。保存モードでの連続運転、8時間の連続運転、Claru AIへの対応は未確認です。詳細は[動作確認状況](docs/status.md)を参照してください。
