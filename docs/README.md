# docs/

システム構成・仕様書([Typst](https://typst.app/)で記述)。`architecture.pdf`は
GitHub上でそのまま閲覧できるようコミット済み。`architecture.typ`を編集したら
必ず再生成してコミットすること(自動化されていない、手動同期)。

```sh
typst compile architecture.typ          # architecture.pdf を再生成
typst watch architecture.typ            # 編集しながらプレビュー
```

依存パッケージ: `codly` 1.3.0, `codly-languages` 0.1.1, `cetz` 0.4.2(初回compile時に
`https://packages.typst.org`から自動取得、要ネットワーク接続)。`cetz`は0.3.1系だと
座標解決でpanicするため0.4.2を使っている。

コードや実際のマニフェストの変更に追従して更新すること。特にPodのroutingや
namespace構成、シークレット管理方針を変えた場合は該当セクションを直すこと。
