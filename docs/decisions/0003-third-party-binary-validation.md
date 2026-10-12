# 0003: 第三者アプリのバイナリを改変しない

## 状況

Minute Dataと同じ画面・通信を持ち、提出だけを無効にした検証アプリがあれば反復試験は容易になります。しかしApp Storeから取得したアプリはコンパイル済みの配布物であり、Xcodeプロジェクトやソースコードを含みません。配布署名ではデバッグ用の`get-task-allow`も無効です。

バイナリやリソースを変更すれば元の署名は成立しません。別チームで再署名しても、bundle identifier、Keychain、App Groups、Push通知、App Attest、バックエンド認証などの前提が変わるため、本番アプリと同じ検証対象にはなりません。

## 決定

App Store版の抽出、復号、パッチ、再署名を、開発または現場運用の前提にしません。開発元からソースまたは検証ビルドを提供された場合だけ、その許諾条件に従って非公開環境で利用し、提供物をこの公開リポジトリへ含めません。

通常運転と検証は、インストール済みの正規アプリをWebDriverAgentから観測する同じ本番アダプターで行います。アプリ固有アダプターは次だけに依存します。

- bundle identifier
- 現在画面を一意に証明するアクセシビリティ要素
- 対象タスクを一意に示す要素
- 各操作後に成立すべき画面状態

画面が既知の状態に一致しない場合、対象要素が0件または複数件の場合、警告・ログイン・権限画面がある場合は操作せず、その端末を`needsAttention`へ移します。

Minute Dataの初期実機確認では、完了時のポリシーに`discardAfterEachChunk`を使用します。ただし、Minute Dataはチャンク完了前からアップロードする可能性があるため、最後のdiscardは「提出や送信が一度も発生しない」ことを保証しません。実アプリで録画を開始する前に、対象アカウント、対象タスク、通信・報酬への影響を確認します。

提出を確定する操作は現時点で実装しません。画面と意味を確認できた場合だけ、Minuteアダプターの完了ポリシーとして追加します。Device WorkerやAppium接続層は変更しません。

## 開発元へ依頼できるもの

- 本番提出を行わないTestFlightまたは開発ビルド
- 合成ユーザーと合成タスクだけを持つステージング組織
- アップロード無効化、または破棄されるステージング保存先
- 30分チャンクを短縮できるテスト設定
- 自動操作に使用できる安定したアクセシビリティ識別子
- WebDriverAgentによる操作の明示的な許可

これらは実機検証の安全性と速度を高めますが、通常運転のコードを別経路にはしません。

## 参考

- [Apple: App code signing process](https://support.apple.com/en-ca/guide/security/sec7c917bf14/web)
- [Apple: Diagnosing issues with entitlements](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements)
- [Appium XCUITest Driver capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)
