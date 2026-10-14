# Claru AI

Claru AIを操作するための操作定義のひな形（`definition.example.json`）です。Claru AIの画面はまだ調べていないので、状態と操作は仮の形で、目印はすべて`REPLACE_WITH_`で始まる値になっています。

使うには、実機でClaru AIの画面を調べ、状態、操作、アプリが自分で進む移り変わりを書き足します。書き方は[操作定義の形式](../../docs/app-operation-format.md)にあります。書き足したら、検証してから使います。

```sh
mkdir -p config/local
cp apps/claru-app/definition.example.json config/local/claru.json
swift run --package-path mac/controller-core field-app --validate-definition config/local/claru.json
```

`REPLACE_WITH_`の値が残っているうちは、検証が通りません。設定ファイルとサービスの登録は、Minute Dataと同じです（[セットアップ](../../docs/setup.md)）。
