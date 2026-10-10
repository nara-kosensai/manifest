// docs/architecture.md を印刷向け(縦向きA4・1段組・10.5pt、シーケンス図ページのみ
// 横向き)に変換したTypstソース。正本は architecture.typ(縦向き・1段組・12pt)。
// この版は architecture.md の内容(シーケンス図を含む)をベースにしており、
// レイアウトのみ異なる派生版。
#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.1": codly-languages
#import "@preview/cetz:0.4.2": canvas, draw

#set page(
  paper: "a4",
  margin: (top: 15mm, bottom: 15mm, left: 15mm, right: 15mm),
  numbering: "1",
  number-align: center,
)

#set text(
  font: ("Noto Serif JP"),
  size: 10.5pt,
  lang: "ja",
  region: "jp",
)
#set par(
  first-line-indent: 1em,
  leading: 0.9em,
  justify: true,
)
#show raw: set text(font: ("HackGen Console NF", "Ubuntu Mono"))

#set heading(numbering: (..nums) => {
  let n = nums.pos()
  if n.len() == 1 {
    "第" + numbering("1", n.at(0)) + "章"
  } else {
    n.map(str).join(".")
  }
})

#show heading.where(level: 1): it => {
  if it.numbering == none {
    pagebreak(weak: true)
    v(1.2em)
    block(text(font: ("Noto Sans JP"), weight: "bold", size: 13pt)[#it.body])
    v(1em)
  } else {
    counter(figure.where(kind: "zu")).update(0)
    counter(figure.where(kind: "hyo")).update(0)
    counter(figure.where(kind: raw)).update(0)
    counter(math.equation).update(0)
    pagebreak(weak: true)
    v(1.2em)
    block(text(font: ("Noto Sans JP"), weight: "bold", size: 13pt)[
      #counter(heading).display() #h(0.5em) #it.body
    ])
    v(1em)
  }
}
#show heading.where(level: 2): it => {
  v(1.2em, weak: true)
  block(text(font: ("Noto Sans JP"), weight: "bold", size: 11pt)[
    #counter(heading).display() #h(0.5em) #it.body
  ])
  v(0.8em, weak: true)
}
#show heading.where(level: 3): it => {
  v(1em, weak: true)
  block(text(font: ("Noto Sans JP"), weight: "bold", size: 10pt)[
    #counter(heading).display() #h(0.5em) #it.body
  ])
  v(0.6em, weak: true)
}

#set list(indent: 1.5em, marker: [•])
#set enum(indent: 1em, numbering: "(1)")

#let fig-num(chapter, n) = numbering("1.1", chapter, n)
#let fig-numbering = n => context {
  let chapter = counter(heading).get().at(0, default: 0)
  fig-num(chapter, n)
}

#show figure.where(kind: "zu"): set figure(
  supplement: [図],
  numbering: fig-numbering,
)
#show figure.where(kind: "hyo"): set figure(
  supplement: [表],
  numbering: fig-numbering,
)
#show figure.where(kind: raw): set figure(
  supplement: [ソースコード],
  numbering: fig-numbering,
)
#show figure.where(kind: raw): it => {
  set figure.caption(position: top)
  show figure.caption: set text(weight: "bold")
  set block(breakable: true)
  it
}

#show figure.caption: it => text(size: 8.5pt)[
  #it.supplement#context it.counter.display(it.numbering)：#it.body
]

#show ref: it => {
  if it.element != none and it.element.func() == figure {
    let el = it.element
    context {
      let chapter = counter(heading).at(el.location()).at(0, default: 0)
      let n = el.counter.at(el.location()).at(0)
      link(el.location(), [#el.supplement#fig-num(chapter, n)])
    }
  } else {
    it
  }
}

#set figure(gap: 0.7em)
#show figure.where(kind: "hyo"): set block(above: 1.5em, below: 1.5em)

#show: codly-init.with()
#codly(
  languages: codly-languages,
  zebra-fill: none,
  fill: rgb(95%, 95%, 95%),
  stroke: 0.6pt + rgb(60%, 60%, 60%),
  number-format: n => text(fill: rgb(45%, 45%, 45%), size: 7pt)[#n],
  radius: 0pt,
)

// ---------------------------------------------------------------------
// 表紙(ノンブルなし)
// ---------------------------------------------------------------------
#set page(numbering: none)
#align(center)[
  #v(4cm)
  #text(font: ("Noto Sans JP"), size: 24pt, weight: "bold")[nara-kosensai]
  #v(0.4em)
  #text(font: ("Noto Sans JP"), size: 14pt)[システム構成・仕様書(印刷版)]
  #v(2.5em)
  #text(size: 10pt)[
    対象リポジトリ: `nara-kosensai/manifest`(旧 `config`)、`fumikun/2026kosensai` \
    最終更新: 2026-08-29 \
    #v(0.3em)
  ]
]
#pagebreak()

#set page(numbering: "1")
#counter(page).update(1)
#outline(title: [目次], indent: auto)
#pagebreak()

= 概要

nara-kosensaiは、単一VPS上のシングルノードk3sクラスタで運用されている。旧構成(VPSネイティブのnginx
と複数のdocker-compose)から全面移行したもので、外部通信は原則Cloudflare Tunnel経由のみとし、クラス
タはノードの公開インターフェースに極力ポートをバインドしない。唯一の例外が本番アプリ
(`nara-kosensai.com` / `www.nara-kosensai.com`)で、CloudflareのOrigin
Authentication(mTLS)を使い、Tunnelを経由せず直接オリジンに到達させる。

このクラスタの設定は4つのリポジトリに分散して管理する。特定サービスに紐づかない共有プラット
フォーム設定・クラスタブートストラップは本リポジトリ(`nara-kosensai/manifest`)に、アプリ/コンテ
ンツ固有の設定はそれぞれのサービスのリポジトリに置く方針である(@repo-table)。

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left),
    table.header([*リポジトリ*], [*内容*]),
    [`nara-kosensai/manifest`\ (本リポジトリ)], [
      クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定
      (`k8s/`：cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook,
      kosensai-form-preview のデプロイ定義)、この仕様書
    ],
    [`fumikun/2026kosensai`], [
      当年アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト
      (`infra/k8s/base/`, `overlays/{prod,test}`)・CI/CD
    ],
    [`nara-kosensai/www`], [
      過去年度(2017--2025)アーカイブサイトの中身とそのイメージビルドCI。デプロイ先マニ
      フェストは本リポジトリ側が保持
    ],
    [`fumikun/kosensai-form-preview`], [
      高専祭掲載情報プレビューツール本体・CI。デプロイ先マニフェストは本リポジトリ側
    ],
  ),
  caption: [設定リポジトリの役割分担],
  kind: "hyo",
) <repo-table>

#text(size: 8.5pt)[
  *リポジトリ名について*：本リポジトリはGitHub上で`nara-kosensai/config`から
  `nara-kosensai/manifest`へリネーム済み(2026年)。旧URL(`.../config.git`)は自動転送
  されるため既存クローンは動作し続けるが、新規クローン・CIは新URLを使うのが望ましい。
]

= アーキテクチャ

== リクエスト経路

外部からのリクエストは、宛先ホストによって2つの異なる経路のいずれかを通る。両方とも最終的に同一の
Traefik Pod(namespace: `kube-system`)へ到達するが、Traefikの中では別々のentrypointとして扱わ
れ、互いに干渉しない(@request-flow に示す)。

#figure(
  canvas(length: 1cm, {
    import draw: *

    rect((3.6, 12.4), (6.4, 13.2), name: "browser")
    content("browser", [ブラウザ])
    line((5, 12.4), (5, 11.7), mark: (end: ">"))

    rect((0.3, 10.9), (9.7, 11.7), name: "cf")
    content("cf", [Cloudflare Edge])

    line((3, 10.9), (2, 9.9), mark: (end: ">"))
    line((7, 10.9), (8, 9.9), mark: (end: ">"))
    content((1.55, 10.35), text(size: 8pt)[本番], anchor: "east")
    content((8.45, 10.35), text(size: 8pt)[それ以外], anchor: "west")

    rect((0.3, 9.1), (3.7, 9.9), name: "nic")
    content("nic", text(size: 9pt)[VPS公開IF\ `ens3:443`])
    rect((6.3, 9.1), (9.7, 9.9), name: "cfd")
    content("cfd", text(size: 9pt)[cloudflared Pod\ `network`])

    line((2, 9.1), (2, 7.9), mark: (end: ">"))
    line((8, 9.1), (8, 6.5), mark: (end: ">"))

    rect((0.3, 6.5), (3.7, 7.9), name: "nft", stroke: (dash: "dashed"))
    content("nft", text(size: 8pt)[nftablesゲート\ iifname=ens3 かつ\ Cloudflare IPのみ許可])
    line((2, 6.5), (2, 5.9), mark: (end: ">"))

    rect((0.3, 4.5), (9.7, 5.9), name: "traefik")
    content("traefik", text(size: 9pt)[Traefik(1 Pod・2 entrypoint)\ `websecure-mtls` / `web`])

    line((2, 4.5), (2, 3.5), mark: (end: ">"))
    line((8, 4.5), (8, 3.5), mark: (end: ">"))

    rect((0.3, 2.3), (4.3, 3.5), name: "prod")
    content("prod", text(size: 9pt)[`prod`])
    rect((5.7, 2.3), (9.7, 3.5), name: "others")
    content("others", text(size: 8.5pt)[`test` / `web-static` / `monitoring`])
  }),
  caption: [本番(mTLS Origin Auth)とそれ以外(Cloudflare Tunnel)、2つの入口経路],
  kind: "zu",
) <request-flow>

@request-flow の通り、`websecure-mtls`だけがホストポートに紐づいたentrypointであり、`web`にはホ
ストへのbindが一切ない。したがって`web`側に残されたIngressRouteは、たとえnftablesのフィルタやクラ
イアント証明書の検証が何らかの理由で回避されたとしても、インターネットからは構造的に到達不可能であ
る(§7 障害と設計判断も参照)。

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left, left),
    table.header([*段階*], [*本番 --- mTLS Origin Auth*], [*それ以外 --- Cloudflare Tunnel*]),
    [対象ホスト],
    [`nara-kosensai.com` / `www.nara-kosensai.com`],
    [`test.*` / `storybook.*` / `grafana.*` / `pgadmin*.*` / `info-check.*`],

    [Cloudflareエッジ],
    [SSL/TLS: Full (strict) + Authenticated Origin Pulls],
    [Cloudflare Tunnel(通常のDNS/SSLモード設定とは独立に動作)],

    [VPSへの入口],
    [公開インターフェース `ens3:443`(hostPort)],
    [`cloudflared` Pod(namespace: `network`)、VPS側からのoutbound接続のみ],

    [フィルタ],
    [
      nftables raw prerouting： `iifname == ens3` かつ `tcp dport 443` かつ
      `saddr ∉ Cloudflare IP` → drop(無応答)
    ],
    [該当なし(公開ポートを一切持たないため到達手段自体が存在しない)],

    [Traefik entrypoint],
    [
      `websecure-mtls` ・hostPort 443 ・サーバ証明書はOrigin CA証明書 ・
      `TLSOption`(`RequireAndVerifyClientCert`)でクライアント証明書を検証
    ],
    [`web` ・ClusterIP :80のみ ・ホストへのbindなし],

    [到達先 namespace],
    [`prod`],
    [`test` / `web-static` / `monitoring`],
  ),
  caption: [2つの入口経路の対比],
  kind: "hyo",
) <path-table>

#figure(
  ```nft
  table ip cloudflare_mtls {
    set cf_ipv4 { type ipv4_addr; flags interval; elements = { ... } }
    chain prerouting {
      type filter hook prerouting priority raw; policy accept;
      iifname "ens3" tcp dport 443 ip saddr != @cf_ipv4 drop
    }
  }
  table ip6 cloudflare_mtls6 {
    set cf_ipv6 { type ipv6_addr; flags interval; elements = { ... } }
    chain prerouting {
      type filter hook prerouting priority raw; policy accept;
      iifname "ens3" tcp dport 443 ip6 saddr != @cf_ipv6 drop
    }
  }
  ```,
  caption: [Cloudflare IP allowlist(nftables、`k3s/cloudflare-ip-allowlist.sh`が生成。IPv4/IPv6で独立したテーブルを持つ)],
  kind: raw,
) <nft-rule>

冪等な全置換方式(新レンジ取得 → 一時ファイル組み立て → 旧テーブル削除 → `nft -f`で
アトミック適用)で動作するため、`curl`失敗時は旧ルールが残るフェイルセーフ側に倒れるが、
テーブル削除後の`nft -f`自体が失敗すると次回timer実行までdropルールが不在になりうる
(既知の課題、`operations.md`参照)。

上記2経路を時系列で見たシーケンス図を@request-sequence に示す。

// ---------------------------------------------------------------------
// シーケンス図: このページには図以外の本文を置かない(単独ページ・横向き・全幅1段組)
// ---------------------------------------------------------------------
#page(flipped: true, columns: 1)[
  #let participants = (
    (x: 1.5, label: [ブラウザ]),
    (x: 6.0, label: [Cloudflare\ Edge]),
    (x: 10.0, label: [VPS公開IF\ (ens3:443)]),
    (x: 14.0, label: [nftables\ ゲート]),
    (x: 18.0, label: [cloudflared\ Pod (network)]),
    (x: 22.0, label: [Traefik\ (websecure-mtls / web)]),
    (x: 26.0, label: [アプリ Pod]),
  )
  #let client = 1.5
  #let cfedge = 6.0
  #let nic = 10.0
  #let nft = 14.0
  #let cfd = 18.0
  #let traefik = 22.0
  #let app = 26.0

  #let top-y = 18.6
  #let bottom-y = 1.6

  #figure(
    canvas(length: 1cm, {
      import draw: *

      // 参加者ボックスとライフライン
      for p in participants {
        rect((p.x - 1.7, top-y), (p.x + 1.7, top-y + 0.9), name: "hdr")
        content("hdr", text(size: 7.5pt)[#p.label])
        line((p.x, top-y), (p.x, bottom-y), stroke: (dash: "dashed", paint: gray))
      }

      // 矢印1本を描くヘルパー。dashed: true で応答(破線)矢印にする
      let msg(from-x, to-x, y, label, dashed: false) = {
        let st = if dashed { (paint: black, dash: "dashed") } else { (paint: black) }
        line((from-x, y), (to-x, y), mark: (end: ">"), stroke: st)
        let mid = (from-x + to-x) / 2
        content((mid, y + 0.28), text(size: 7pt)[#label])
      }

      // alt/else/end の区切り線
      let divider(y, label) = {
        line((0.2, y), (27.3, y), stroke: (dash: "dotted", paint: gray))
        content((0.4, y + 0.3), anchor: "west", text(size: 7.5pt, weight: "bold", fill: rgb(30%, 30%, 30%))[#label])
      }

      msg(client, cfedge, 17.4, [HTTPS GET https://\<host\>/...])

      divider(16.5, [alt 本番ホスト(nara-kosensai.com / www) --- mTLS Origin Auth])
      msg(cfedge, nic, 15.5, [オリジンへ直接接続(Full strict + Authenticated Origin Pulls)])
      msg(nic, nft, 14.5, [パケット到達(iifname=ens3, tcp dport 443)])
      msg(nft, traefik, 13.5, [saddr∈Cloudflare IP のみ転送(不一致はsilent drop)])
      msg(traefik, app, 12.5, [namespace: prod へルーティング(クライアント証明書検証後)])
      msg(app, traefik, 11.5, [レスポンス], dashed: true)

      divider(10.6, [else それ以外(test.* / storybook.* / grafana.* / pgadmin*.* / info-check.*) --- Cloudflare Tunnel])
      msg(cfedge, cfd, 9.6, [Tunnel経由で転送(cloudflaredのoutbound接続を再利用)])
      msg(cfd, traefik, 8.6, [web entrypoint(ClusterIP:80、ホストへのbindなし)])
      msg(traefik, app, 7.6, [namespace: test / web-static / monitoring へルーティング])
      msg(app, traefik, 6.6, [レスポンス], dashed: true)

      divider(5.7, [end])

      msg(traefik, cfedge, 4.7, [レスポンス], dashed: true)
      msg(cfedge, client, 3.7, [レスポンス], dashed: true)

      content((13.5, 2.4), text(size: 7pt, fill: rgb(45%, 45%, 45%))[
        nftablesで不一致となったパケットはTraefikに到達する前にサイレントdropされる(応答を一切返さない)
      ])
    }),
    caption: [リクエスト処理のシーケンス],
    kind: "zu",
  ) <request-sequence>
]

== namespace構成

#figure(
  table(
    columns: (auto, auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left, left),
    table.header([*namespace*], [*代表ホスト*], [*内容*]),
    [`prod`], [`nara-kosensai.com` / `www`], [frontend・backend・db (StatefulSet)・website・pgadmin],
    [`test`], [`test.nara-kosensai.com`], [frontend・backend・db・website・pgadmin],
    [`web-static`], [`storybook.*` / `info-check.*`], [www-archive(過去年度アーカイブ)・storybook・form-preview],
    [`monitoring`], [`grafana.nara-kosensai.com`], [grafana・loki・prometheus・node-exporter・kube-state-metrics],
    [`network`], [---], [cloudflared(公開Web用Tunnel)],
    [`kube-system`], [---], [Traefik(k3s同梱)・CoreDNS],
  ),
  caption: [namespace一覧],
  kind: "hyo",
) <ns-table>

管理元は`prod`/`test`が`2026kosensai`リポジトリのCI、それ以外が`manifest`リポジトリのCI。
`web-static`/`prod`/`test`のIngressRouteは、過去年度アーカイブ(`web-static` namespace)のService
をcross-namespaceで参照する。単一テナント運用のクラスタであるため、Traefikの
`providers.kubernetesCRD.allowCrossNamespace: true`を有効にしている。

== Ingressルーティング(旧nginxからの移植)

旧nginx `default.conf`のパス単位ルーティング・リダイレクトは、TraefikのIngressRoute/
Middlewareとして`2026kosensai`リポジトリに移植した。nginxのlongest-prefix-wins相当を
明示的な`priority`(数値が大きいほど高優先)で再現している(@ingress-priority)。

#figure(
  table(
    columns: (auto, auto, 1fr, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (center, left, left, left),
    table.header([*priority*], [*マッチ条件(prod)*], [*Middleware*], [*転送先*]),
    [100], [`Host(www.*)`], [`www-to-apex`], [apexへ301],
    [90], [`/` `/2026` `/2026/app`], [`redirect-root`等], [301],
    [80], [`PathPrefix(/2026/app/)`], [`security-headers`], [frontend :3000],
    [70], [`/2009..2016, /2021`], [`old-years-redirect`], [学校公式サイトへ301],
    [60], [`PathPrefix(/2026/)`], [`security-headers`(testは`strip-2026-prefix`も)], [website :80],
    [10], [`PathPrefix(/)`catch-all], [`security-headers`, `archive-404`], [www-archive :80],
  ),
  caption: [prod IngressRouteのルーティング優先度],
  kind: "hyo",
) <ingress-priority>

`strip-2026-prefix`はtestのwebsite Serviceのみに必要(素のリバースプロキシ転送のため)。
`archive-404`はcatch-all到達を404として`web-static`の`www-archive`が持つ
`/2025/404.html`を返すerrors Middleware。`security-headers`はCSP等を全ホスト共通で
付与する。pgAdminは`web`entrypoint(Tunnel経由)のみを使い、Cloudflare Accessで保護する
(Traefik側のMiddlewareではない)。

`cloudflared`(namespace: `network`)のConfigMapは`web`entrypoint行きの全ホストを一律
`http://traefik.kube-system.svc.cluster.local:80`へ転送し、ホスト単位の実際の振り分けは
各namespaceのIngressRouteに委ねている。本番ホスト(`nara-kosensai.com` / `www`)は
Origin Authentication移行完了時点でこのConfigMapのingressエントリから削除済み。

= ネットワーク・セキュリティ

== 公開ポート

VPSの公開インターフェースにbindされるポートは443/tcpのみ。80/tcpはTraefikの`web`
entrypointがClusterIPのみで待ち受けており、ホストには一切bindされない。

443/tcpへのアクセス制限は、VPSプロバイダ側とホスト側で役割が異なる。

+ *VPSプロバイダのファイアウォール*：ポート単位の制限のみ(443/tcpと管理用SSH以外を閉じる)。
  送信元IPアドレスによるフィルタリングは行っていない。
+ *ホスト側nftables*(`k3s/cloudflare-ip-allowlist.sh`、@nft-rule)：送信元IPアドレスの
  フィルタリングはこの層のみが担う。Cloudflareが公開しているIPv4/IPv6レンジ
  (`https://www.cloudflare.com/ips-v4`, `ips-v6`)を、raw prerouting段階でパケットの
  送信元インターフェース(`iifname`、デフォルトルートから動的に解決)と組み合わせて判定する。
  マッチしない場合はTCPハンドシェイクにもTLSアラートにも至らずサイレントにdropする。
  IPv4/IPv6それぞれ独立したテーブルを持つ。systemd timer(`cloudflare-ip-allowlist.timer`)
  が日次でレンジを再取得し、`manifest`リポジトリへのpush時にもCIが都度再実行する。

Cloudflare IPアローリストの実体は完全にnftables側にある点に注意(VPSプロバイダ側の
ファイアウォールは補完しない)。

== TLS / mTLS

- *オリジンサーバ証明書*：Cloudflare Origin CA証明書。SANは`nara-kosensai.com`と
  `*.nara-kosensai.com`をカバー(有効期限2041年)。`2026kosensai`リポジトリの
  `production-vps` environmentのGitHub Environment Secret(`CF_ORIGIN_CERT` /
  `CF_ORIGIN_KEY`)として保管し、CIが`prod` namespaceに`cloudflare-origin-cert`
  (`kubernetes.io/tls`)Secretとして投入する。
- *クライアント証明書検証*：Traefikの`TLSOption`(namespace: `network`、名前
  `cloudflare-mtls`)が、Cloudflareが公開しているAuthenticated Origin Pulls用CA証明書
  (`k8s/base/network/cloudflare-aop-ca.yaml`、公開情報のためgit管理)に対して
  `RequireAndVerifyClientCert`を要求する。FreeプランのためCloudflare管理のzone-level
  証明書を使用する(per-hostnameのカスタムクライアント証明書は非対応)。

#figure(
  ```yaml
  spec:
    entryPoints:
      - websecure-mtls
    tls:
      secretName: cloudflare-origin-cert
      options:
        name: cloudflare-mtls
        namespace: network
  ```,
  caption: [prod IngressRouteのTLS設定(2026kosensai `infra/k8s/overlays/prod/ingress/ingressroute.yaml`)],
  kind: raw,
) <ingressroute-tls>

== RBAC

Prometheusとkube-state-metricsは、それぞれ専用のServiceAccountで動作し、read-onlyの
`get`/`list`/`watch`のみを許可するClusterRoleを持つ(`k8s/base/monitoring/prometheus-rbac.yaml`、
`kube-state-metrics.yaml`)。既定のServiceAccountには何の権限も付与しない。

kube-state-metrics用ClusterRoleは`list`/`watch`のみだが対象に`secrets`を含む(存在・
メタデータの可視化目的、書き込み権限はなし)。Prometheus用はさらにkube-apiserver/
kubelet/cAdvisorのメトリクスエンドポイントにServiceAccountトークンで認証する
(`kubelet`ジョブのみTLS検証を`insecure_skip_verify: true`で緩めている)。

= シークレット管理

Infisical(自己ホスト)は2026-08-29付けで完全に廃止した。現在の方針を@secrets-table に示す。

#figure(
  table(
    columns: (auto, 1fr, auto),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left, left),
    table.header([*対象*], [*保管場所*], [*理由*]),
    [DB / pgAdmin / CORS等\ (`app-env`)],
    [`manifest`リポジトリ直下の\ `prod.env` / `staging.env`\ (平文コミット)],
    [DBはClusterIP限定で\ 外部到達不能],

    [GHCR pullトークン],
    [GitHub Environment Secret\ (`production-vps` / `test-vps`)],
    [CIからのみ必要],

    [Cloudflare Origin CA証明書],
    [GitHub Environment Secret\ (`production-vps`、環境限定)],
    [本番専用の機微情報],

    [Cloudflare Access\ クライアント資格情報],
    [GitHub Actions Secret\ (管理用SSH Tunnel専用)],
    [app-envとは無関係],

    [Grafana管理者パスワード等],
    [k8s Secret(`grafana-secrets`)\ ブートストラップ時に手動投入],
    [gitignore対象、\ 循環依存を避けるため],

    [Cloudflare Tunnel\ 資格情報],
    [k8s Secret(`cloudflared-credentials`)\ ブートストラップ時に手動投入],
    [CLI操作でのみ得られる\ `credentials.json`],

    [GHCR pullトークン\ (`web-static`用)],
    [k8s Secret(`ghcr-pull`)\ ブートストラップ時に手動投入],
    [privateイメージのpull用],
  ),
  caption: [シークレットの保管場所と方針],
  kind: "hyo",
) <secrets-table>

`manifest`リポジトリのCIが`prod.env` / `staging.env`をVPSの`/home/github/app-env/`に同期
し、`2026kosensai`リポジトリのCIがそのパスを直接`--from-env-file`で参照する。このため
`manifest`側のCIが`2026kosensai`側より先に一度動いている必要がある。`prod`/`test`の
`ghcr-pull`は`2026kosensai`のCI自身がデプロイの都度`GHCR_PULL_TOKEN`から再生成する
(こちらは一度きりの手動投入ではない)。

= CI/CDパイプライン

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left),
    table.header([*リポジトリ / ブランチ*], [*処理内容*]),
    [`manifest` → `main`],
    [
      k3sブートストラップマニフェスト再配置 → Cloudflare IP allowlist再実行 →
      `kubectl apply -k k8s/overlays/shared` → 各Deploymentのrollout確認
    ],
    [`2026kosensai` → `prod`],
    [
      backend/frontend/website/storybook全イメージを無条件でbuild/push(path-filter
      なし)→ GHCR pullトークン・Origin CA証明書をGitHub Environment Secretsから取得 →
      `kubectl apply -k infra/k8s/overlays/prod` → rollout確認
    ],
    [`2026kosensai` → `test`],
    [
      `dorny/paths-filter`で変更検知(backend/frontend/website)→ 変更分のみbuild/push・
      apply → `.../test/ingress`は毎回無条件apply → rollout確認
      (pgAdmin用Cloudflare Accessは別途手動設定)
    ],
    [`2026kosensai` → PR],
    [
      `pr-check.yml`：Node側(pnpm+Turborepo)の`lint typecheck build`、Go側の
      `go build` / `go test`。デプロイなし
    ],
  ),
  caption: [CI/CDパイプライン一覧],
  kind: "hyo",
) <cicd-table>

いずれもGitHub ActionsからVPSへは、管理用のCloudflare Access Tunnel(`cloudflared access tcp`)
経由でSSH接続する。これは公開Web用のTunnel(namespace `network`のcloudflared)とは別物で、VPS
側からのoutbound接続であるため、§3のnftables allowlistとは無関係に動作する。`storybook`
イメージは`deploy-prod.yml`がbuild/pushするが、`web-static`への反映(`kubectl apply`と
`rollout restart`)は`manifest`側CIが担う(prod/test共有singletonのため)。

= 監視

Prometheus(namespace `monitoring`)は次をスクレイプする。

- `node-exporter`：ノードのCPU/メモリ/ディスク
- `traefik`：Traefik自身のメトリクス(現状9100番ポートが未公開のため要修正、既知の課題)
- `kube-state-metrics`：Pod/Deployment/StatefulSetのオブジェクト状態
  (Running/Restart回数/Readyレプリカ数)
- `kubernetes-apiservers`：kube-apiserverのリクエストレイテンシ・エラー率
- `kubelet` / `kubernetes-cadvisor`：ノード・Pod単位のリソース使用量

いずれも`kubernetes_sd_configs`によるin-cluster discoveryと、ServiceAccountトークン
(`/var/run/secrets/kubernetes.io/serviceaccount/`)による認証を使う標準的な構成。Grafanaの
Prometheus/Lokiデータソースは自動プロビジョニングしておらず、初回のみ手動追加が必要
(`http://prometheus:9090`, `http://loki:3100`、いずれも`monitoring` namespace内)。ログは
Grafana Alloy(DaemonSet、`k3s/alloy-logging.yaml`)が全namespaceのPodログをLokiへ出荷する。

#figure(
  table(
    columns: (auto, auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left, left),
    table.header([*コンポーネント*], [*Retain?*], [*備考*]),
    [`prometheus`(10Gi)], [されない], [メトリクスは再収集可能],
    [`loki`(10Gi)], [されない], [`retention: 72h`],
    [`grafana`(5Gi)], [*される*], [ダッシュボード等は再構築コスト高],
  ),
  caption: [監視コンポーネントのPVCとreclaimPolicy],
  kind: "hyo",
) <monitoring-pvc-table>

node-exporterは`hostNetwork: true` / `hostPID: true`のDaemonSetで旧`network_mode: host`
相当を再現。GrafanaはGitHub OAuthログインを有効化し、allow-list外のGitHubアカウントは
サインアップできない。

= 障害と設計判断

== nftablesルールのインターフェーススコープ(2026-08-29)

Origin Authentication導入時に追加したnftablesルールが、当初`tcp dport 443`のみで判定してお
り、送信元インターフェースを指定していなかった。クラスタ内部には`kubernetes.default.svc`
(ClusterIP、`10.43.0.1:443`)を含む複数のClusterIPがたまたま443番を使っており、このルールは
Pod→APIサーバー間の内部通信まで巻き込んでdropしてしまった。

結果として`helm-install-traefik`ジョブ(Traefikの新しいエントリーポイント設定を適用するための
Helmインストール)がAPIサーバーに到達できず、インストール失敗→アンインストール→再インストール
のクラッシュループに陥り、Traefik自体が消滅。本番環境が約1時間ダウンした(Cloudflareエラー
521/526)。

*対処*：ルールを`iifname`(ノードの実際の外部NIC。ハードコードではなく`ip route show default`
から都度動的に解決)でスコープした(@nft-rule)。クラスタ内部のトラフィックは定義上この物理イン
ターフェースを通らないため、どのClusterIPが443番を使っていても衝突しない。

同時に、Traefikのコンテナポート・Service公開ポートでも類似の衝突が発生していた
(`websecure-mtls`をchartのデフォルト`websecure`と同じ8443番/443番で定義していたため)。コンテ
ナポートは8444番、Service公開は`expose.default: false`(hostPortのみ、Service経由の公開はそも
そも不要)に変更して解消した。

== VPS再起動によるホスト名変化とk3sノード名の固定(2026-08-28)

VPSプロバイダのメンテナンス再起動でOSの静的ホスト名が`x162-43-87-201`から`kosensai`に
変化し、k3sが同じ物理マシンを*別のノード*として新規登録した。既存PersistentVolumeは
すべて`nodeAffinity`で旧ノード名を固定的に参照(作成後変更不可)していたため、PVCを使う
全Pod(`db`, `loki`, `grafana`, `prometheus`等)が新ノードにスケジュールできず`Pending`
のまま止まった。

*対処*：9個のPV再作成は本番データを巻き込むリスクが高いため、
`/etc/systemd/system/k3s.service`の`ExecStart`に`--node-name x162-43-87-201`を追加し、
*k3s側のノード名をOSホスト名から独立させて固定した*。以後OSホスト名が変わってもノード名は
不変のため、既存PVの`nodeAffinity`と食い違わない。詳細は`operations.md`「2.」を参照。

= リファレンス

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 6pt,
    align: (left, left),
    table.header([*項目*], [*値*]),
    [Kubernetesディストリビューション], [k3s(シングルノード、`--disable=servicelb`)],
    [k3sノード名], [`x162-43-87-201`に固定(OSホスト名から独立)],
    [Ingressコントローラ], [Traefik 3.7(k3s同梱Helmチャート)],
    [CNI], [flannel(k3s標準)],
    [ストレージ], [local-path(既定、Delete)、local-path-retain(Retain、DB/backend/grafana用)],
    [公開ポート], [443/tcpのみ(80/tcpはClusterIP限定で非公開)],
    [Traefik `websecure-mtls`], [containerPort 8444, hostPort 443, expose.default: false],
    [Traefik `web`], [containerPort 8000相当(chart既定), ClusterIP:80のみ],
    [管理用SSH], [Cloudflare Access Tunnel(公開Web用Tunnelとは別物、outbound-only)],
    [Prometheus/Grafana/Loki], [v2.51.0 / 11.0.0 / 3.0.0],
    [node-exporter/kube-state-metrics], [v1.8.0 / v2.13.0],
    [Loki保持期間], [72h],
    [関連リポジトリ], [`manifest`(本リポジトリ)、`2026kosensai`、`www`、`kosensai-form-preview`],
  ),
  caption: [設定値リファレンス],
  kind: "hyo",
) <ref-table>
