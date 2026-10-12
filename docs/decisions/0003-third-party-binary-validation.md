# 0003: 第三者アプリのバイナリを改変しない

## 状況

対象アプリと同じ画面・通信を持ち、提出だけを無効にした検証用のアプリがあれば、反復試験は容易になります。しかしApp Storeから取得したアプリはコンパイル済みの配布物であり、Xcodeプロジェクトやソースコードを含みません。配布署名ではデバッグ用の`get-task-allow`も無効です。

バイナリやリソースを変更すれば元の署名は成立しません。別チームで再署名しても、bundle identifier、Keychain、App Groups、Push通知、App Attest、バックエンド認証などの前提が変わるため、本番アプリと同じ検証対象にはなりません。

## 決定

App Store版の抽出、復号、パッチ、再署名を、開発または現場運用の前提にしません。開発元からソースまたは検証ビルドを提供された場合だけ、その許諾条件に従って非公開環境で利用し、提供物をこの公開リポジトリへ含めません。

通常運転と検証は、インストール済みの正規アプリをWebDriverAgentから観測・操作する共通処理で行います。アプリ別の操作定義には、次の情報を記述します。

- bundle identifier
- 現在画面を一意に証明するアクセシビリティ要素
- 対象タスクを一意に示す要素
- タップ対象と、現在画面・目標状態に応じた次の操作

画面や操作対象を一意に判定できない場合、または操作定義に登録した警告・ログイン・権限の要素を検出した場合は操作せず、その端末を`needsAttention`へ移します。

## 参考

- [Apple: App code signing process](https://support.apple.com/en-ca/guide/security/sec7c917bf14/web)
- [Apple: Diagnosing issues with entitlements](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements)
- [Appium XCUITest Driver capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)
