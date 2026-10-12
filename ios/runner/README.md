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

## 既知の制約

Minute Dataのfeatured carouselはCore Animationを継続するため、通常のXCTest操作ではアイドル待ちに約60秒かかりました。現在のテストはXCTestの非公開ランナーフックを使い、操作前後のquiescence待ちを外しています。このフックが利用できないXcodeでは通常の操作へフォールバックします。
