# 0003: サードパーティアプリのバイナリを改変しない

## 状況

対象アプリと同じ画面と通信を持ち、提出のみを無効にした検証用アプリがあれば、反復試験は容易になります。しかし、App Storeから取得したアプリはコンパイル済みの配布物であり、Xcodeプロジェクトやソースコードを含みません。配布用の署名では、デバッグ用の`get-task-allow`も無効です。

バイナリやリソースを変更すると、元の署名は無効になります。別のTeamで再署名しても、Bundle Identifier、Keychain、App Groups、プッシュ通知、App Attest、バックエンドの認証などの前提が変わるため、本番アプリと同じ検証対象にはなりません。

## 決定

App Store版の抽出、復号、パッチ、再署名を、開発や現場運用の前提にしません。開発元からソースコードまたは検証用ビルドの提供を受けた場合に限り、その許諾条件に従って非公開の環境で利用し、提供物を本公開リポジトリには含めません。

通常運用と検証は、インストール済みの正規アプリをWebDriverAgentから読み取り・操作する共通処理で行います。アプリ別の操作定義には、次の情報を記述します。

- Bundle Identifier
- 画面の状態を識別するアクセシビリティ要素
- 状態間を結ぶタップと、その影響
- 撮影対象のタスクを示す要素

画面の状態や操作対象を1つに特定できない場合、またはiOSのダイアログが表示されている場合は、操作を行わず、その端末を`needsAttention`に移行します。

## 参考

- [Apple: App code signing process](https://support.apple.com/en-ca/guide/security/sec7c917bf14/web)
- [Apple: Diagnosing issues with entitlements](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements)
- [Appium XCUITest Driver capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)
