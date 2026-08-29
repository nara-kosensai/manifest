# docs/

システム構成・仕様書([Typst](https://typst.app/)で記述)。`architecture.pdf`は
GitHub上でそのまま閲覧できるようコミット済み。`architecture.typ`を編集したら
必ず再生成してコミットすること(自動化されていない、手動同期)。

```sh
typst compile architecture.typ          # architecture.pdf を再生成
typst watch architecture.typ            # 編集しながらプレビュー
```

コードや実際のマニフェストの変更に追従して更新すること。特にPodのroutingや
namespace構成、シークレット管理方針を変えた場合は該当セクションを直すこと。
