# Claru AI

Claru AI用の操作定義のテンプレート（`definition.example.json`）です。Claru AIの画面は未調査のため、状態と操作は仮のもので、識別子はすべて`REPLACE_WITH_`で始まる値になっています。

使用するには、実機でClaru AIの画面を調査し、状態、操作、自動遷移を追記します。書式は[操作定義の形式](../../docs/app-operation-format.md)を参照してください。追記後、検証してから使用します。

```sh
mkdir -p config/local
cp apps/claru-app/definition.example.json config/local/claru.json
swift run --package-path mac/controller-core field-app --validate-definition config/local/claru.json
```

`REPLACE_WITH_`の値が残っている間は、検証でエラーになります。設定ファイルの作成とサービスの登録は、Minute Dataと同じです（[セットアップ](../../docs/setup.md)）。
