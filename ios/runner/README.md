# iOS UI runner

このXcodeプロジェクトは、Macから登録済みiPhone上の第三者アプリを観測・操作するためのUIテストランナーです。

## 前提

- MacにXcodeがインストールされていること
- iPhoneとMacが信頼済みで、Developer Modeが有効であること
- 対象アプリがインストールされ、初回ログインと必要な権限許可が完了していること
- Apple Development署名に使うチームへ端末が登録されていること

署名チーム、UDID、プロビジョニングファイルはコミットしません。

## プロジェクト確認

```sh
xcodebuild \
  -project FieldAppOrchestratorUITests.xcodeproj \
  -scheme FieldAppOrchestratorUITests \
  -list
```

## Minute Dataの安全なスモークテスト

`testLaunchAndInspectAccessibilityTree`はMinute Dataを起動し、画面とアクセシビリティツリーを保存します。録画は開始しません。

```sh
xcodebuild \
  -project FieldAppOrchestratorUITests.xcodeproj \
  -scheme FieldAppOrchestratorUITests \
  -destination 'id=<IPHONE_UDID>' \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  test \
  -only-testing:FieldAppOrchestratorUITests/MinuteDataUITests/testLaunchAndInspectAccessibilityTree
```

`testInspectFirstFeaturedTask`は先頭のfeatured taskを開いて詳細画面を記録しますが、`start task`は押しません。

## 提出を伴わない反復テスト

`MockTaskAppUITests`は[`../mock-app`](../mock-app/README.md)を対象にします。録画やネットワーク通信を行わず、3秒後に30分終了相当の画面遷移を発生させます。実アプリの`start task`を押す検証はここへ追加しません。

### 複数実機での並列テスト

[`../../tools/test_mock_devices.sh`](../../tools/test_mock_devices.sh)は、指定した各iPhoneへ安全なモックをインストールし、端末ごとに独立したXcodeプロセスとDerivedDataを使って、開始・停止・再開・停止を並列実行します。

各端末は、MacとのペアリングとDeveloper Modeの有効化を最初に済ませてください。署名チームと端末IDはコマンド実行時だけ渡し、ファイルへ保存しません。

```sh
FAO_DEVELOPMENT_TEAM=<TEAM_ID> \
  ../../tools/test_mock_devices.sh <IPHONE_UDID_1> <IPHONE_UDID_2>
```

実行ログとDerivedDataは`/private/tmp`配下の端末別ディレクトリへ残ります。失敗時は、その端末のログだけを確認できます。

## 既知の制約

Minute Dataのfeatured carouselはCore Animationを継続するため、通常のXCTest操作ではアイドル待ちに約60秒かかりました。現在のテストはXCTestの非公開ランナーフックを使い、操作前後のquiescence待ちを外しています。このフックが利用できないXcodeでは通常の操作へフォールバックします。
