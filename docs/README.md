# docs/

システム構成・仕様書。正本は[Typst](https://typst.app/)版(`architecture.typ`)で、
`architecture.pdf`はGitHub上でそのまま閲覧できるようコミット済み。`architecture.md`は
GitHub上でのブラウズや検索、Markdown対応ツールでの参照用に用意したコピーで、内容は
Typst版と一致させる。**いずれかを編集したら、もう一方と`architecture.pdf`も必ず同じ
内容に更新してコミットすること(自動化されていない、手動同期)。**

```sh
typst compile architecture.typ          # architecture.pdf を再生成
typst watch architecture.typ            # 編集しながらプレビュー
```

`architecture-print.typ` / `architecture-print.pdf`は同内容を横向きA4・2段組・10ptで
組んだ印刷向け派生版(シーケンス図は単独ページ・全幅で配置)。正本ではないため、
`architecture.md`を更新した場合の追従は任意。再生成は`typst compile architecture-print.typ`。

依存パッケージ: `codly` 1.3.0, `codly-languages` 0.1.1, `cetz` 0.4.2(初回compile時に
`https://packages.typst.org`から自動取得、要ネットワーク接続)。`cetz`は0.3.1系だと
座標解決でpanicするため0.4.2を使っている。

コードや実際のマニフェストの変更に追従して更新すること。特にPodのroutingや
namespace構成、シークレット管理方針を変えた場合は該当セクションを直すこと。

[operations.md](operations.md)は日々のトラブルシュート向けの運用マニュアル(Markdownのみ、
Typst版なし)。発生が懸念される/実際に発生したトラブルの症状・原因・診断・対処法をまとめている。
恒久的な設計変更を行った場合は、そちらだけでなく`architecture.md` / `architecture.typ`の
「障害と設計判断」節にも反映すること。
