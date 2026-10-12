# 0003: 第三者アプリのバイナリ改変を検証基盤にしない

## 状況

現行の安全なモックは、提出を発生させずにXCUITestの接続と基本操作を確認できます。一方、Minute Data固有のタスク選択、録画後処理、アップロード待ち、エラー画面まで再現していないため、実アプリの8時間運転を証明する代替物にはなりません。

App Storeから取得したアプリはコンパイル済みの配布物であり、Xcodeプロジェクトやソースコードを含みません。配布署名ではデバッグ用の`get-task-allow`も無効です。バイナリやリソースを変更すれば元の署名は成立せず、別チームで再署名するとbundle identifier、Keychain、App Groups、Push通知、App Attestなどのアプリとバックエンドの前提も変わります。

## 決定

App Store版の抽出、復号、パッチ、再署名を、開発または現場運用の前提にしません。開発元からソースまたは検証ビルドを提供された場合だけ、その許諾条件に従って非公開環境で利用します。提供物をこの公開リポジトリへ含めません。

検証を次の三層に分けます。

1. 現行iOSモックは、WebDriverAgentの署名、接続、要素検索、タップが実機で機能することだけを検証する。
2. Mac側には、保存済みの画面状態を再生して30分チャンク、後処理、切断、再接続、未知画面を高速に発生させる振る舞いシミュレーターを追加する。固有の画面資料と端末情報はローカルに保存し、公開リポジトリへ含めない。
3. 実アプリの完全な終了・再開フローと8時間連続運転は、開発元が用意したステージング組織、提出無効ビルド、または明示的に許可されたテスト環境で確認する。

通常運転の実装は、第三者アプリの内部コードではなく、WebDriverAgentから観測できる画面状態だけに依存します。画面が既知の状態に一致しなければ操作せず、その端末を`needs_attention`へ移します。

## 開発元へ依頼するもの

- 本番提出を行わないTestFlightまたは開発ビルド
- 合成ユーザーと合成タスクだけを持つステージング組織
- アップロード無効化、または破棄されるステージング保存先
- 30分チャンクを短縮できるテスト設定
- 自動操作に使用できる安定したアクセシビリティ識別子
- XCUITestまたはWebDriverAgentによる操作の明示的な許可

## 参考

- [Apple: App code signing process](https://support.apple.com/en-ca/guide/security/sec7c917bf14/web)
- [Apple: Diagnosing issues with entitlements](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements)
- [Appium XCUITest Driver capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)
