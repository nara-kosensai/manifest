#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.1": codly-languages
#import "@preview/cetz:0.4.2": canvas, draw

#set page(
  paper: "a4",
  margin: (top: 20mm, bottom: 30mm, left: 20mm, right: 20mm),
  numbering: "1",
  number-align: center,
)

#set text(
  font: ("Noto Serif JP"),
  size: 12pt,
  lang: "ja",
  region: "jp",
)
#set par(
  first-line-indent: 1em,
  leading: 0.95em,
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
    // 目次/図目次/表目次などoutlineが内部生成する見出し。章番号は付けない。
    pagebreak(weak: true)
    v(1.5em)
    block(text(font: ("Noto Sans JP"), weight: "bold", size: 15pt)[#it.body])
    v(1.3em)
  } else {
    counter(figure.where(kind: "zu")).update(0)
    counter(figure.where(kind: "hyo")).update(0)
    counter(figure.where(kind: raw)).update(0)
    counter(math.equation).update(0)
    pagebreak(weak: true)
    v(1.5em)
    block(text(font: ("Noto Sans JP"), weight: "bold", size: 15pt)[
      #counter(heading).display() #h(0.5em) #it.body
    ])
    v(1.3em)
  }
}
#show heading.where(level: 2): it => {
  v(1.5em, weak: true)
  block(text(font: ("Noto Sans JP"), weight: "bold", size: 13pt)[
    #counter(heading).display() #h(0.5em) #it.body
  ])
  v(1em, weak: true)
}
#show heading.where(level: 3): it => {
  v(1.2em, weak: true)
  block(text(font: ("Noto Sans JP"), weight: "bold", size: 11.5pt)[
    #counter(heading).display() #h(0.5em) #it.body
  ])
  v(0.8em, weak: true)
}

#set list(indent: 2em, marker: [•])
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

#show figure.caption: it => text(size: 10.5pt)[
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

#set figure(gap: 0.8em)
#show figure.where(kind: "hyo"): set block(above: 2em, below: 2em)

#show: codly-init.with()
#codly(
  languages: codly-languages,
  zebra-fill: none,
  fill: rgb(95%, 95%, 95%),
  stroke: 0.6pt + rgb(60%, 60%, 60%),
  number-format: n => text(fill: rgb(45%, 45%, 45%), size: 8pt)[#n],
  radius: 0pt,
)

// ---------------------------------------------------------------------
// 表紙(ノンブルなし)
// ---------------------------------------------------------------------
#set page(numbering: none)
#align(center)[
  #v(6cm)
  #text(font: ("Noto Sans JP"), size: 26pt, weight: "bold")[nara-kosensai]
  #v(0.4em)
  #text(font: ("Noto Sans JP"), size: 16pt)[システム構成・仕様書]
  #v(3em)
  #text(size: 11pt)[
    対象リポジトリ: `nara-kosensai/manifest`(旧 `config`)、`fumikun/2026kosensai` \
    最終更新: 2026-08-29
  ]
]
#pagebreak()

#set page(numbering: "1")
#counter(page).update(1)
#outline(title: [目次], indent: auto)

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
    inset: 8pt,
    align: (left, left),
    table.header([*リポジトリ*], [*内容*]),
    [`nara-kosensai/manifest`\ (本リポジトリ)], [
      クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定
      (`k8s/`：cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook,
      kosensai-form-preview のデプロイ定義)、この仕様書。CIは`main`ブランチへのpushで発火
    ],
    [`fumikun/2026kosensai`], [
      当年アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト
      (`infra/k8s/base/`, `overlays/{prod,test}`)・CI/CD。`prod`/`test`ブランチへの
      pushでそれぞれ本番/検証環境にデプロイ
    ],
    [`nara-kosensai/www`], [
      過去年度(2017--2025)アーカイブサイトの中身と、そのイメージをビルドする
      Dockerfile・CI。デプロイ先マニフェスト(`k8s/base/web-static/archive-*.yaml`)は
      本リポジトリ側が保持する
    ],
    [`fumikun/kosensai-form-preview`], [
      高専祭掲載情報プレビューツール本体・CI。デプロイ先マニフェストは本リポジトリ側
      (`k8s/base/web-static/form-preview-*.yaml`)
    ],
  ),
  caption: [設定リポジトリの役割分担],
  kind: "hyo",
) <repo-table>

#block(inset: (top: 0.4em))[
  #text(size: 10.5pt)[
    *リポジトリ名について*：本リポジトリはGitHub上で`nara-kosensai/config`から
    `nara-kosensai/manifest`へリネーム済み(2026年)。リネーム後もGitHubは旧URL
    (`.../config.git`)から新URLへの参照を自動転送するため、旧URLを`origin`に設定した
    既存クローンはfetch/pushとも動作し続けるが、新規クローンやCIの`checkout`アクションは
    新URL(`nara-kosensai/manifest`)を使うのが望ましい。ドキュメント内では現在の正式名
    `manifest`を主に用い、旧名`config`は文脈上必要な場合のみ併記する。
  ]
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
    inset: 8pt,
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
  caption: [Cloudflare IP allowlist(nftables、`k3s/cloudflare-ip-allowlist.sh`が生成。
    IPv4/IPv6で独立したテーブルを持つ)],
  kind: raw,
) <nft-rule>

`cloudflare-ip-allowlist.sh`は冪等な全置換方式で動作する：新レンジ取得 →
一時ファイルに新rulesetを組み立て → 既存の`cloudflare_mtls` / `cloudflare_mtls6`テーブルを
削除 → `nft -f`で新rulesetをアトミックに適用、という順序を取る。`curl`でのレンジ取得に失敗
した場合は`set -euo pipefail`によりテーブル削除前に異常終了するため、古いルールが残った
フェイルセーフ側に倒れる。一方、テーブル削除後の`nft -f`適用自体が失敗した場合は、次回の
timer実行(最大24時間+ランダム遅延)までdropルールが存在しない期間が生まれうる(既知の課題、
`operations.md`参照)。

== namespace構成

#figure(
  table(
    columns: (auto, auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left, left),
    table.header([*namespace*], [*代表ホスト*], [*内容*]),
    [`prod`], [`nara-kosensai.com` / `www`], [frontend・backend・db (StatefulSet)・website・pgadmin],
    [`test`], [`test.nara-kosensai.com`], [frontend・backend・db・website・pgadmin],
    [`web-static`], [`storybook.*` / `info-check.*`], [www-archive(過去年度アーカイブ)・storybook・form-preview],
    [`monitoring`], [`grafana.nara-kosensai.com`], [grafana・loki・prometheus・node-exporter・kube-state-metrics],
    [`network`], [---], [cloudflared(公開Web用Tunnel)],
    [`argocd`], [`argocd.nara-kosensai.com`], [ArgoCD本体(GitOpsコントローラ)],
    [`kube-system`], [---], [Traefik(k3s同梱)・CoreDNS],
  ),
  caption: [namespace一覧],
  kind: "hyo",
) <ns-table>

`prod`/`test`/`monitoring`/`network`/`web-static`の実際のマニフェストapplyはArgoCD
(namespace: `argocd`)がgitを直接pullして行う。`argocd`自体のインストールと、各namespaceの
作成・Secret投入(ArgoCDの管理対象外)は引き続き各リポジトリのpush-CIが担う
(詳細は@cicd-table を参照)。`web-static`/`prod`/`test`のIngressRouteは、過去年度アーカイブ
(`web-static` namespace)のServiceをcross-namespaceで参照する。単一テナント運用のクラスタ
であるため、Traefikの`providers.kubernetesCRD.allowCrossNamespace: true`を有効にしている。

== Ingressルーティング(旧nginxからの移植)

旧構成のnginx `default.conf`のserver blockが持っていたパス単位のルーティング・リダイレクト
ロジックは、TraefikのIngressRoute/Middlewareとして`2026kosensai`リポジトリ側に移植した
(`infra/k8s/overlays/{prod,test}/ingress/`)。nginxのlongest-prefix-wins相当を明示的な
`priority`(数値が大きいほど高優先)で再現している(@ingress-priority)。

#figure(
  table(
    columns: (auto, auto, 1fr, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (center, left, left, left),
    table.header([*priority*], [*マッチ条件(prod, Host=nara-kosensai.com)*], [*Middleware*], [*転送先*]),
    [100], [`Host(www.nara-kosensai.com)`], [`www-to-apex`(恒久リダイレクト)], [apexへ301],
    [90], [`Path(/)` / `Path(/2026)` / `Path(/2026/app)`], [`redirect-root` 等(末尾`/`付与)], [301],
    [80], [`PathPrefix(/2026/app/)`], [`security-headers`], [frontend :3000],
    [70], [`PathPrefix(/2009..2016, /2021)`], [`old-years-redirect`], [学校公式サイトへ301],
    [60], [`PathPrefix(/2026/)`], [`security-headers`\ (testのみ`strip-2026-prefix`も併用)], [website :80],
    [10], [`PathPrefix(/)`(catch-all)], [`security-headers`, `archive-404`], [www-archive :80\ (namespace: web-static)],
  ),
  caption: [prod IngressRouteのルーティング優先度(testもほぼ同構成、mTLSではなくTunnel経由)],
  kind: "hyo",
) <ingress-priority>

補足:

- *`strip-2026-prefix`*：当年サイト(Astro)は`base: "/2026"`でビルドされ、生成HTML内の
  アセット参照は`/2026/...`前提。prodは旧nginxの`alias`相当の動作(内部的にプレフィックス
  除去)をwebsiteコンテナ側のビルド設定で吸収しているためMiddleware不要だが、testの
  website Serviceは素のリバースプロキシ転送のため明示的な`StripPrefix`が必要
  (`infra/k8s/base/website/website-stripprefix.yaml`)。
- *`archive-404`*：`Host + PathPrefix(/)`のcatch-allにヒットした結果を404として、
  `web-static` namespaceの`www-archive` Serviceが持つ`/2025/404.html`をerrors
  Middleware経由で返す(旧nginxの`root /var/www/html/` + `/404.html` aliasの再現)。
- *`security-headers`* Middleware(`k8s/base/ingress/security-headers.yaml`、
  `2026kosensai`リポジトリにも同一内容を複製配置)は、`X-Frame-Options`,
  `X-Content-Type-Options`, `Strict-Transport-Security`に加え、Google Tag Manager /
  Google Fonts / YouTube埋め込みを許可するCSPを全ホスト共通で付与する。
- *pgAdmin*(`pgadmin.nara-kosensai.com` / `pgadmin-test.*`)は`web`
  entrypointのみを使い(Tunnel経由)、TraefikのMiddlewareではなくCloudflare Access
  (Tunnelのpublic hostnameに紐づく認証ポリシー、ダッシュボード側で一度きり設定)で保護する。

=== Cloudflare Tunnel側のingress設定

`web`entrypoint行きの全ホストは、`cloudflared`(namespace: `network`)の
ConfigMap(`k8s/base/network/cloudflared-configmap.yaml`)で一律
`http://traefik.kube-system.svc.cluster.local:80`へ転送されるよう設定してあり、ホスト単位の
実際の振り分けは前述の各namespaceのIngressRouteに委ねている。Tunnelのingressルールに現れる
ホストは`test.*`, `storybook.*`, `info-check.*`, `pgadmin.*`, `pgadmin-test.*`,
`grafana.*`で、末尾は`service: http_status:404`のcatch-allで閉じる。本番ホスト
(`nara-kosensai.com` / `www`)は、Origin Authentication移行が完了した時点でこの
ConfigMapのingressエントリから削除済み(現在Tunnel経由で到達するのは`test`/`web-static`/
`monitoring`配下のホストのみ)。

= ネットワーク・セキュリティ

== 公開ポート

VPSの公開インターフェースにbindされるポートは443/tcpのみ。80/tcpはTraefikの`web`
entrypointがClusterIPのみで待ち受けており、ホストには一切bindされない。

443/tcpへのアクセス制限は、VPSプロバイダ側とホスト側で役割が異なる。

+ *VPSプロバイダのファイアウォール(セキュリティグループ)*：ポート単位の制限のみを行う
  (443/tcpと管理用SSH以外を閉じる)。送信元IPアドレスによるフィルタリングは行っていない
  ---つまりこの層だけでは、Cloudflare以外の任意のIPから443/tcpへ到達できてしまう。
+ *ホスト側nftables*(`k3s/cloudflare-ip-allowlist.sh`、@nft-rule)：送信元IPアドレスの
  フィルタリングは、この層が唯一かつ全面的に担っている。Cloudflareが公開しているIPv4/IPv6
  レンジ(`https://www.cloudflare.com/ips-v4`, `ips-v6`)を、raw prerouting段階でパケット
  の送信元インターフェース(`iifname`、デフォルトルートから動的に解決)と組み合わせて判定する。
  マッチしない場合はTCPハンドシェイクにもTLSアラートにも至らずサイレントにdropする。IPv4/IPv6
  それぞれ独立したテーブル(`ip cloudflare_mtls` / `ip6 cloudflare_mtls6`)を持つ。systemd
  timer(`cloudflare-ip-allowlist.timer`)が日次でレンジを再取得し、`manifest`リポジトリへの
  push時にもCIが都度再実行する。

したがって、Cloudflare IPアローリストの実体は完全にnftables側にある。このスクリプトが失敗
した状態が長く続くと、VPSプロバイダ側のファイアウォールはそれを補ってくれない(運用マニュアル
`operations.md`の「1. Cloudflare IPアローリストの更新不具合」を参照)。

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

kube-state-metrics用ClusterRoleは`list`/`watch`のみだが、対象リソースには`secrets`が
含まれる(Secret自体の値ではなく、存在・メタデータを可視化するため標準的に必要とされる範囲)。
書き込み権限は一切付与していない。Prometheus用ClusterRoleはノード・Pod・Service・
Endpointsの`get`/`list`/`watch`に加え、kube-apiserver/kubelet/cAdvisorのメトリクス
エンドポイントにアクセスするためServiceAccountトークンをbearer tokenとして使う
(`kubernetes_sd_configs`によるin-cluster discovery、TLS検証は`kubelet`ジョブのみ
`insecure_skip_verify: true`で緩めている。単一ノード・単一テナント運用のため許容)。

= シークレット管理

Infisical(自己ホスト)は2026-08-29付けで完全に廃止した。現在の方針を@secrets-table に示す。

#figure(
  table(
    columns: (auto, 1fr, auto),
    stroke: 0.5pt + gray,
    inset: 8pt,
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

    [Cloudflare Tunnel\ (公開Web用)資格情報],
    [k8s Secret(`cloudflared-credentials`、\ namespace: `network`)\ ブートストラップ時に手動投入],
    [`cloudflared tunnel create`で生成される\ `credentials.json`は\ CLI操作でのみ得られる],

    [GHCR pullトークン\ (`web-static` namespace用)],
    [k8s Secret(`ghcr-pull`)\ ブートストラップ時に手動投入],
    [`www-archive`/`storybook`/`form-preview`\ イメージがprivateなため],

    [ArgoCD用GitHub Deploy Key\ (`manifest`/`2026kosensai`各リポジトリ)],
    [k8s Secret(`argocd`namespace、\ `argocd.argoproj.io/secret-type: repository`\ ラベル)ブートストラップ時に手動投入],
    [ArgoCDがprivateリポジトリを\ 読み取り専用でpullするため],
  ),
  caption: [シークレットの保管場所と方針],
  kind: "hyo",
) <secrets-table>

`manifest`リポジトリのCIが`prod.env` / `staging.env`をVPSの`/home/github/app-env/`に同期
し、`2026kosensai`リポジトリのCIがそのパスを直接`--from-env-file`で参照する。このため
`manifest`側のCIが`2026kosensai`側より先に一度動いている必要がある。同様に、`web-static`
namespaceの`ghcr-pull` Secretは`manifest`側CIが適用する`k8s/overlays/shared`が
Deploymentを作成する前提として存在している必要があり、これも一度きりの手動投入である。

`prod`/`test` namespaceの`ghcr-pull`(2026kosensaiアプリのイメージpull用)は
`2026kosensai`リポジトリのCI自身が、GitHub Environment Secret(`GHCR_PULL_TOKEN`)から
デプロイの都度`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`で
再生成する(こちらは一度きりの手動投入ではなくCI管理)。トークン期限切れ時の症状・対処は
`operations.md`の「3. GHCR pullトークンの期限切れ・権限エラー(403)」を参照。

= CI/CDパイプライン

2026年9月にpush型(CIが直接`kubectl apply`)からArgoCDによるpull型GitOpsへ移行した。
マニフェスト本体のapplyはすべてArgoCDが担い、各リポジトリのpush-CIは「ArgoCDのスコープ外の
もの(ArgoCD自体のインストール、namespace作成、Secret投入)の同期」と「イメージbuild/push +
マニフェストのイメージタグ更新をgitにcommit&push」だけを行う。

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left),
    table.header([*リポジトリ / ブランチ*], [*処理内容*]),
    [`manifest` → `main`],
    [
      k3sブートストラップマニフェスト再配置 → Cloudflare IP allowlist再実行 →
      `k8s/`をVPSへrsync(ArgoCDが直接gitからpullするためapplyはしない)→
      ArgoCD自体を`kubectl apply -k k8s/bootstrap/argocd`
    ],
    [`2026kosensai` → `prod`],
    [
      backend/frontend/website/storybook全イメージを無条件でbuild/push(path-filterは
      使わない)→ `kustomize edit set image`でoverlayのタグ更新 → そのまま`prod`
      ブランチにcommit&push(`[skip ci]`)→ namespace作成・GHCR pullトークン/Origin CA
      証明書由来のSecret投入
    ],
    [`2026kosensai` → `test`],
    [
      変更検知(`dorny/paths-filter`でbackend/frontend/website差分を判定)→ 変更された
      コンポーネントのみimage build/push → 変更分のみ`kustomize edit set image`でタグ更新 →
      そのまま`test`ブランチにcommit&push(`[skip ci]`)→ namespace作成・GHCR pullトークン
      由来のSecret投入(pgAdmin用Cloudflare Accessは別途手動設定)
    ],
    [`2026kosensai` → PR(任意ブランチ)],
    [
      `pr-check.yml`：Node側(pnpm + Turborepo)の`lint typecheck build`、Go側
      (`app/backend`)の`go build` / `go test`。デプロイは行わない
    ],
  ),
  caption: [CI/CDパイプライン一覧],
  kind: "hyo",
) <cicd-table>

ArgoCD(namespace: `argocd`、`argocd.nara-kosensai.com`でCloudflare Tunnel + Access経由公開)は
`manifest`リポジトリの`k8s/argocd-apps/`が定義するApplication(App-of-apps、`root-app`)を
通じて、以下をgitから直接pullし`automated`(prune+selfHeal)でsyncする。

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left, left),
    table.header([*Application*], [*source repo / path*], [*対象*]),
    [`platform-shared`], [`manifest` / `k8s/overlays/shared`], [monitoring/network/web-static/ingress],
    [`app-prod` / `app-test`], [`2026kosensai`(`prod`/`test`) / `infra/k8s/overlays/{prod,test}/app-dynamic`], [backend/frontend/db/pgadmin],
    [`website-prod` / `website-test`], [同上 / `.../website`], [website],
    [`ingress-prod` / `ingress-test`], [同上 / `.../ingress`], [IngressRoute/Middleware],
  ),
  caption: [ArgoCD Application一覧],
  kind: "hyo",
) <argocd-apps-table>

各リポジトリへの読み取りアクセスはリポジトリ単位のSSH Deploy Keyで行う(`argocd`namespace内に
`argocd.argoproj.io/secret-type: repository`ラベル付きSecretとして登録、README.md参照)。
CIは`git push`後のArgoCDの実際のsync/rollout成否を待たない点に注意
(現状はArgoCD UI/通知で監視する運用、CI失敗としては検知しない)。

いずれもGitHub ActionsからVPSへは、管理用のCloudflare Access Tunnel(`cloudflared access tcp`)
経由でSSH接続する。これは公開Web用のTunnel(namespace `network`のcloudflared)とは別物で、VPS
側からのoutbound接続であるため、§3のnftables allowlistとは無関係に動作する。SSH接続に使う
`cloudflared`本体は、`manifest`/`2026kosensai`いずれのワークフローも、実行の都度GitHub
Releases APIから最新バイナリをダウンロードし、リリースアセットのSHA-256ダイジェストと突き合わ
せて検証してから使う(`deploy-test.yml`のみ`2026.7.2`にバージョン固定)。

`2026kosensai`の`storybook`イメージは`deploy-prod.yml`がbuild/push(タグは`:latest`と
コミットSHA)まで行うが、実際に`web-static` namespaceへ反映(`kubectl apply`)するのは
`manifest`リポジトリ側のCIである。`storybook`はprod/test共有のsingletonであり、
`2026kosensai`が管理するnamespace(`prod`/`test`)には属さないため。`manifest`側のCIは
毎回`deployment/storybook`と`deployment/form-preview`を`rollout restart`してから
`:latest`タグを再pullさせる(イメージダイジェストが変わってもタグ名は`:latest`のまま
なのでrestartしないとPodが更新されない)。

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
    inset: 8pt,
    align: (left, left, left),
    table.header([*コンポーネント*], [*Retain?*], [*備考*]),
    [`prometheus`(10Gi)], [されない\ (`local-path`)], [メトリクスは再収集可能なため失っても許容],
    [`loki`(10Gi)], [されない\ (`local-path`)], [`retention_period: 72h`(=3日)。ログも同様に許容],
    [`grafana`(5Gi)], [*される*\ (`local-path-retain`)], [ダッシュボード定義・アノテーション等は\ 再構築コストが高い],
  ),
  caption: [監視コンポーネントのPVCとreclaimPolicy(§5「シークレット管理」で扱う\ `app`側のDB/backendも同じ`local-path-retain`を使う)],
  kind: "hyo",
) <monitoring-pvc-table>

node-exporterは旧構成の`network_mode: host`相当を、DaemonSetに`hostNetwork: true` /
`hostPID: true`と`/proc`, `/sys`, `/`のhostPathマウントを組み合わせて再現している(単一
ノードだが、将来ノードが増えても自動的に追随する構成)。Grafanaは`GF_AUTH_GITHUB_ENABLED`
によるGitHub OAuthログインを有効化しており、`GF_AUTH_GITHUB_ALLOWED_USERS`で許可した
GitHubアカウントのみサインアップ・ログインできる(allow-list外のアカウントは弾かれる)。
管理者パスワードとGitHub OAuthのクライアントシークレットは`grafana-secrets` Secret
(@secrets-table)からのみ注入し、それ以外の非機微な設定はDeploymentマニフェストに直接
書く。

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

VPSプロバイダ側のメンテナンスと思われるOS更新(カーネル`6.1.0-49-cloud-amd64` →
`6.12.105+deb13-cloud-amd64`)を伴う再起動で、OSの静的ホスト名が`x162-43-87-201`から
`kosensai`に変化した。k3sはデフォルトでノード名にOSホスト名をそのまま使うため、同じ物理
マシンが*別のノード*として新規登録され、旧ノードオブジェクトは`NotReady`のまま残った。

このクラスタは`local-path`(ノードローカルストレージ)を使っており、既存のPersistentVolume
はすべて`nodeAffinity`で旧ノード名を固定的に参照していた(この`nodeAffinity`は作成後
変更不可)。新ノード名はこのaffinityにマッチしないため、PVCを使う全Pod(`db`, `loki`,
`grafana`, `prometheus`等)が新ノードにスケジュールできず`Pending`のまま止まり、CIの
`rollout status`待ちがタイムアウトする形で表面化した。

*対処*：9個のPVすべてを削除→再作成するのは本番データを巻き込むリスクが高いため、代わりに
`/etc/systemd/system/k3s.service`の`ExecStart`に`--node-name x162-43-87-201`を追加し、
*k3s側のノード名をOSホスト名から独立させて固定した*。以後OSホスト名が再び変わっても、
k3sは常に同じノード名として登録されるため、既存PVの`nodeAffinity`と食い違わない。

== push型CIからArgoCD(GitOps)への移行(2026-09-02)

デプロイをCIから直接`kubectl apply`するpush型から、ArgoCDがgitを直接pullしてapplyするpull型
(GitOps)へ移行した。狙いは主に2点：(1) VPS上の実際の状態とgitの内容が乖離した場合に
`selfHeal`で自動的に検知・是正できるようにする、(2) 各リポジトリのCIから`rsync`+
`kubectl apply`+複数の`rollout status`待ちという長い手続きを排除し、CIの責務を「イメージ
build/push + マニフェストのタグ更新をgitに反映する」ことだけに縮小する。

*ArgoCD自体はGitOps管理の対象外とした*(`k8s/bootstrap/argocd/`、push-CIが恒久的に適用)。
理由は、ArgoCDの管理対象にArgoCD自身を含めると、ArgoCDが何らかの理由で壊れた場合にArgoCD
自身を使った復旧ができなくなるため(chicken-and-egg問題)。これは既存の`k3s/`ブートストラップ
層(k3s本体・Traefik設定など)がpush-CI管理のまま残っている設計判断と同じ理由による。

Secret類(`app-env`, `ghcr-pull`, `grafana-secrets`, `cloudflared-credentials`,
`cloudflare-origin-cert`)はこれまで通りgitにコミットせずkustomizeの`resources`にも含めない
運用を維持した。ArgoCDの管理対象は各kustomize baseのresourcesに列挙されたものだけなので、
これらのSecretはArgoCDの`selfHeal`によるprune対象にもならず、CIが引き続き
`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`で投入する。

*既知のトレードオフ*：CIは`git push`後、ArgoCDによる実際のsync/rolloutの成否を待たない
(移行前は`kubectl rollout status`でCIジョブ自体が失敗検知していた)。現状はArgoCD UI/通知での
監視に委ねている。将来的に`argocd app wait`をCloudflare Access Tunnel経由でCIから呼ぶ形に
拡張し、CIでの失敗検知を復元する余地がある(未実装)。

この事例は、シングルノードk3sでも「ノードの同一性」をOSホスト名任せにすると壊れうる、という
運用上の教訓として設計判断に残す。応急処置・恒久対策の詳細な手順は`operations.md`
「2. VPS再起動でホスト名が変わりk3sノードが二重化する」を参照。

= リファレンス

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left),
    table.header([*項目*], [*値*]),
    [Kubernetesディストリビューション], [k3s(シングルノード、`--disable=servicelb`)],
    [k3sノード名], [`x162-43-87-201`に固定(`--node-name`、OSホスト名から独立。§7参照)],
    [Ingressコントローラ], [Traefik 3.7(k3s同梱Helmチャート)],
    [CNI], [flannel(k3s標準)],
    [ストレージ], [local-path(既定、reclaimPolicy: Delete)、\ local-path-retain(reclaimPolicy: Retain、DB/backend/grafana用)],
    [公開ポート], [443/tcpのみ(80/tcpはClusterIP限定で非公開)],
    [Traefik `websecure-mtls`], [containerPort 8444, hostPort 443, expose.default: false],
    [Traefik `web`], [containerPort 8000相当(chart既定), ClusterIP:80のみ],
    [管理用SSH], [Cloudflare Access Tunnel(公開Web用Tunnelとは別物、outbound-only)],
    [Prometheus / Grafana / Loki], [`prom/prometheus:v2.51.0` / `grafana/grafana:11.0.0` / `grafana/loki:3.0.0`],
    [node-exporter / kube-state-metrics], [`prom/node-exporter:v1.8.0` / `registry.k8s.io/kube-state-metrics:v2.13.0`],
    [Loki保持期間], [`retention_period: 72h`(3日)],
    [関連リポジトリ], [`nara-kosensai/manifest`(本リポジトリ、旧`config`)、\ `fumikun/2026kosensai`、`nara-kosensai/www`、\ `fumikun/kosensai-form-preview`],
  ),
  caption: [設定値リファレンス],
  kind: "hyo",
) <ref-table>
