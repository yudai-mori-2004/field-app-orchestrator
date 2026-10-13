# Claru AIの操作定義

Claru AIを操作するための操作定義のひな形です。Claru AIの画面はまだ調べていないため、状態と操作は仮の形で、目印はすべて`REPLACE_WITH_`の値になっています。

実機でClaru AIの画面を調べ、状態、操作、アプリが自分で進む移り変わりを書き足してから使います。書き方は[操作定義の形式](../../docs/app-operation-format.md)にあります。

```sh
mkdir -p config/local
cp apps/claru-app/definition.example.json config/local/claru.json
swift run --package-path mac/controller-core field-app \
  --validate-definition config/local/claru.json
```

起動するときは、端末ごとに`FAO_DEVICE_ID`と`FAO_DEVICE_LABEL`を変えます。`caffeinate -i`は、動いている間Macをスリープさせません。

```sh
FAO_DEVICE_ID=<IPHONE_UDID> \
FAO_DEVICE_LABEL=claru-01 \
caffeinate -i swift run --package-path mac/controller-core field-app \
  --definition config/local/claru.json
```
