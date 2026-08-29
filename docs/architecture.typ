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

設定は2つのリポジトリで管理する。

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left),
    table.header([*リポジトリ*], [*内容*]),
    [`nara-kosensai/manifest`], [
      クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定
      (`k8s/`：cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook,
      kosensai-form-preview)、この仕様書
    ],
    [`fumikun/2026kosensai`], [
      アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト
      (`infra/k8s/base/`, `overlays/{prod,test}`)・CI/CD
    ],
  ),
  caption: [設定リポジトリの役割分担],
  kind: "hyo",
) <repo-table>

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
  ```,
  caption: [Cloudflare IP allowlist(nftables、`k3s/cloudflare-ip-allowlist.sh`が生成)],
  kind: raw,
) <nft-rule>

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
    [`kube-system`], [---], [Traefik(k3s同梱)・CoreDNS],
  ),
  caption: [namespace一覧],
  kind: "hyo",
) <ns-table>

管理元は`prod`/`test`が`2026kosensai`リポジトリのCI、それ以外が`manifest`リポジトリのCI。
`web-static`/`prod`/`test`のIngressRouteは、過去年度アーカイブ(`web-static` namespace)のService
をcross-namespaceで参照する。単一テナント運用のクラスタであるため、Traefikの
`providers.kubernetesCRD.allowCrossNamespace: true`を有効にしている。

= ネットワーク・セキュリティ

== 公開ポート

VPSの公開インターフェースにbindされるポートは443/tcpのみ。80/tcpはTraefikの`web`
entrypointがClusterIPのみで待ち受けており、ホストには一切bindされない。

443/tcpへのアクセスは二重に制限している。

+ *VPSプロバイダのセキュリティグループ*：Cloudflareが公開しているIPv4/IPv6レンジ
  (`https://www.cloudflare.com/ips-v4`, `ips-v6`)のみ許可。
+ *ホスト側nftables*(`k3s/cloudflare-ip-allowlist.sh`、@nft-rule)：同じCloudflare IPレンジ
  を、raw prerouting段階でパケットの送信元インターフェース(`iifname`、デフォルトルートから
  動的に解決)と組み合わせて判定する。マッチしない場合はTCPハンドシェイクにもTLSアラートにも
  至らずサイレントにdropする。systemd timer(`cloudflare-ip-allowlist.timer`)が日次でレンジ
  を再取得し、`manifest`リポジトリへのpush時にもCIが都度再実行する。

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
  ),
  caption: [シークレットの保管場所と方針],
  kind: "hyo",
) <secrets-table>

`manifest`リポジトリのCIが`prod.env` / `staging.env`をVPSの`/home/github/app-env/`に同期
し、`2026kosensai`リポジトリのCIがそのパスを直接`--from-env-file`で参照する。このため
`manifest`側のCIが`2026kosensai`側より先に一度動いている必要がある。

= CI/CDパイプライン

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
      `kubectl apply -k k8s/overlays/shared` → 各Deploymentのrollout確認
    ],
    [`2026kosensai` → `prod`],
    [
      イメージbuild/push → GHCR pullトークン・Origin CA証明書をGitHub Secretsから取得 →
      `kubectl apply -k infra/k8s/overlays/prod`(backend/frontend/website個別に
      path-filter判定)→ rollout確認
    ],
    [`2026kosensai` → `test`],
    [同上(test namespace、pgAdmin用Cloudflare Accessは別途手動設定)],
  ),
  caption: [CI/CDパイプライン一覧],
  kind: "hyo",
) <cicd-table>

いずれもGitHub ActionsからVPSへは、管理用のCloudflare Access Tunnel(`cloudflared access tcp`)
経由でSSH接続する。これは公開Web用のTunnel(namespace `network`のcloudflared)とは別物で、VPS
側からのoutbound接続であるため、§3のnftables allowlistとは無関係に動作する。

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

= リファレンス

#figure(
  table(
    columns: (auto, 1fr),
    stroke: 0.5pt + gray,
    inset: 8pt,
    align: (left, left),
    table.header([*項目*], [*値*]),
    [Kubernetesディストリビューション], [k3s(シングルノード)],
    [Ingressコントローラ], [Traefik 3.7(k3s同梱Helmチャート)],
    [CNI], [flannel(k3s標準)],
    [ストレージ], [local-path(既定)、local-path-retain(データ保護が必要なPVC用)],
    [公開ポート], [443/tcpのみ(80/tcpはClusterIP限定で非公開)],
    [Traefik `websecure-mtls`], [containerPort 8444, hostPort 443, expose.default: false],
    [Traefik `web`], [containerPort 8000相当(chart既定), ClusterIP:80のみ],
    [管理用SSH], [Cloudflare Access Tunnel(公開Web用Tunnelとは別物、outbound-only)],
  ),
  caption: [設定値リファレンス],
  kind: "hyo",
) <ref-table>
