# docs/

システム構成・仕様書([Typst](https://typst.app/)で記述)。

```sh
typst compile architecture.typ          # architecture.pdf を生成
typst watch architecture.typ            # 編集しながらプレビュー
```

コードや実際のマニフェストの変更に追従して更新すること。特にPodのroutingや
namespace構成、シークレット管理方針を変えた場合は該当セクションを直すこと。
