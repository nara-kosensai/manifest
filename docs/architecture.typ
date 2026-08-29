#set document(title: "nara-kosensai システム構成・仕様書", author: "nara-kosensai")
#set page(
  paper: "a4",
  margin: (x: 2.4cm, y: 2.6cm),
  numbering: "1 / 1",
  header: context if here().page() > 1 [
    #set text(size: 8pt, fill: rgb("#6b7684"))
    #smallcaps[nara-kosensai システム構成・仕様書]
  ],
)
#set text(
  font: ("Noto Sans JP", "Noto Sans"),
  lang: "ja",
  size: 10.3pt,
)
#show raw: set text(font: ("Noto Sans Mono CJK JP", "DejaVu Sans Mono"))
#set par(justify: true, leading: 0.68em, spacing: 1.1em)
#show table.cell: set par(justify: false)
#set heading(numbering: "1.1")
#show heading: set text(font: ("Noto Sans JP", "Noto Sans"))
#show heading.where(level: 1): it => {
  v(1.4em, weak: true)
  block(text(size: 15pt, weight: "bold", it))
  v(0.2em)
}
#show heading.where(level: 2): it => {
  v(1em, weak: true)
  block(text(size: 12pt, weight: "bold", it))
}
#show link: set text(fill: rgb("#c8551f"))

#let mono(s) = raw(s)
#let box_(title, body, fill: rgb("#f4f6f8"), stroke_: rgb("#c3ced9")) = block(
  fill: fill,
  stroke: 1pt + stroke_,
  radius: 4pt,
  inset: 10pt,
  width: 100%,
)[
  #text(weight: "bold", size: 9.8pt)[#title]
  #if body != none [
    #v(0.3em)
    #text(size: 9pt, fill: rgb("#55677a"))[#body]
  ]
]
#let accentbox(title, body) = box_(title, body, fill: rgb("#fbe9de"), stroke_: rgb("#c8551f"))

// ---------------------------------------------------------------------

#align(center)[
  #v(2cm)
  #text(size: 24pt, weight: "bold")[nara-kosensai]
  #v(0.3em)
  #text(size: 15pt, fill: rgb("#55677a"))[システム構成・仕様書]
  #v(1.2em)
  #text(size: 10pt, fill: rgb("#8695a4"))[
    対象リポジトリ: `nara-kosensai/manifest`(旧 `config`)、`fumikun/2026kosensai` \
    最終更新: 2026-08-29
  ]
]
#v(2.5cm)
#outline(indent: auto, title: "目次")
#pagebreak()

= 概要

nara-kosensaiは、単一VPS上のシングルノードk3sクラスタで運用されている。旧構成(VPSネイティブのnginx +
複数のdocker-compose)から全面移行したもので、外部通信は原則Cloudflare Tunnel経由のみとし、
クラスタはノードの公開インターフェースに極力ポートをバインドしない。唯一の例外が本番アプリ
(`nara-kosensai.com` / `www.nara-kosensai.com`)で、CloudflareのOrigin Authentication(mTLS)を
使い、Tunnelを経由せず直接オリジンに到達させる。

設定は2つのリポジトリで管理する。

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt + rgb("#c3ced9"),
  inset: 8pt,
  align: (left, left),
  table.header([*リポジトリ*], [*内容*]),
  [`nara-kosensai/manifest`], [
    クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定
    (`k8s/`: cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook,
    kosensai-form-preview)、この仕様書
  ],
  [`fumikun/2026kosensai`], [
    アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト
    (`infra/k8s/base/`, `overlays/{prod,test}`)・CI/CD
  ],
)

= アーキテクチャ

== リクエスト経路

外部からのリクエストは、宛先ホストによって2つの異なる経路のいずれかを通る。両方とも最終的に
同一のTraefik Pod(namespace: `kube-system`)へ到達するが、Traefikの中では別々の
entrypointとして扱われ、互いに干渉しない。

#table(
  columns: (auto, 1fr, 1fr),
  stroke: 0.5pt + rgb("#c3ced9"),
  inset: 8pt,
  align: (left, left, left),
  table.header([*段階*], [*本番 — mTLS Origin Auth*], [*それ以外 — Cloudflare Tunnel*]),
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
    nftables raw prerouting: \
    `iifname == ens3` かつ `tcp dport 443` かつ \
    `ip saddr ∉ Cloudflare公開IPレンジ` → drop(無応答)
  ],
  [該当なし(公開ポートを一切持たないため、外部からの直接到達手段自体が存在しない)],

  [Traefik entrypoint],
  [
    `websecure-mtls` \
    ・hostPort 443 \
    ・サーバ証明書: Cloudflare Origin CA証明書 \
    ・`TLSOption`(`RequireAndVerifyClientCert`)でCloudflareの
    クライアント証明書を検証
  ],
  [
    `web` \
    ・ClusterIP :80のみ \
    ・ホストへのbindなし
  ],

  [到達先 namespace],
  [`prod`],
  [`test` / `web-static` / `monitoring`],
)

#v(0.4em)
#text(size: 9pt, fill: rgb("#55677a"))[
  *ポイント*: `websecure-mtls`だけがホストポートに紐づいたentrypointであり、`web`にはホストへの
  bindが一切ない。したがって`web`側に残されたIngressRouteは、たとえnftablesのフィルタや
  クライアント証明書の検証が何らかの理由で回避されたとしても、インターネットからは構造的に
  到達不可能である(§6 障害と設計判断も参照)。
]

== namespace構成

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt + rgb("#c3ced9"),
  inset: 8pt,
  align: (left, left, left),
  table.header([*namespace*], [*代表ホスト*], [*内容*]),
  [`prod`], [`nara-kosensai.com` / `www`], [frontend · backend · db (StatefulSet) · website · pgadmin],
  [`test`], [`test.nara-kosensai.com`], [frontend · backend · db · website · pgadmin],
  [`web-static`], [`storybook.*` / `info-check.*`], [www-archive(過去年度アーカイブ)· storybook · form-preview],
  [`monitoring`], [`grafana.nara-kosensai.com`], [grafana · loki · prometheus · node-exporter · kube-state-metrics],
  [`network`], [—], [cloudflared(公開Web用Tunnel)],
  [`kube-system`], [—], [Traefik(k3s同梱)· CoreDNS],
)

管理元は`prod`/`test`が`2026kosensai`リポジトリのCI、それ以外が`manifest`リポジトリのCI。
`web-static`/`prod`/`test`のIngressRouteは、過去年度アーカイブ(`web-static` namespace)の
Serviceをcross-namespaceで参照する。単一テナント運用のクラスタであるため、Traefikの
`providers.kubernetesCRD.allowCrossNamespace: true`を有効にしている。

= ネットワーク・セキュリティ

== 公開ポート

VPSの公開インターフェースにbindされるポートは443/tcpのみ。80/tcpはTraefikの`web`
entrypointがClusterIPのみで待ち受けており、ホストには一切bindされない。

443/tcpへのアクセスは二重に制限している。

+ *VPSプロバイダのセキュリティグループ*: Cloudflareが公開しているIPv4/IPv6レンジ
  (`https://www.cloudflare.com/ips-v4`, `ips-v6`)のみ許可。
+ *ホスト側nftables*(`k3s/cloudflare-ip-allowlist.sh`): 同じCloudflare IPレンジを、
  raw prerouting段階でパケットの送信元インターフェース(`iifname`、デフォルトルートから
  動的に解決)と組み合わせて判定する。マッチしない場合はTCPハンドシェイクにも
  TLSアラートにも至らずサイレントにdropする。systemd timer(`cloudflare-ip-allowlist.timer`)が
  日次でレンジを再取得し、`manifest`リポジトリへのpush時にもCIが都度再実行する。

== TLS / mTLS

- *オリジンサーバ証明書*: Cloudflare Origin CA証明書。SANは`nara-kosensai.com`と
  `*.nara-kosensai.com`をカバー(有効期限 2041年)。`2026kosensai`リポジトリの
  `production-vps` environmentのGitHub Environment Secret(`CF_ORIGIN_CERT` /
  `CF_ORIGIN_KEY`)として保管し、CIが`prod` namespaceに`cloudflare-origin-cert`
  (`kubernetes.io/tls`)Secretとして投入する。
- *クライアント証明書検証*: Traefikの`TLSOption`(namespace: `network`、名前
  `cloudflare-mtls`)が、Cloudflareが公開しているAuthenticated Origin Pulls用CA証明書
  (`k8s/base/network/cloudflare-aop-ca.yaml`、公開情報のためgit管理)に対して
  `RequireAndVerifyClientCert`を要求する。FreeプランのためCloudflare管理の
  zone-level証明書を使用(per-hostnameのカスタムクライアント証明書は非対応)。

== RBAC

Prometheusとkube-state-metricsは、それぞれ専用のServiceAccountで動作し、read-onlyの
`get`/`list`/`watch`のみを許可するClusterRoleを持つ(`k8s/base/monitoring/prometheus-rbac.yaml`、
`kube-state-metrics.yaml`)。既定のServiceAccountには何の権限も付与しない。

= シークレット管理

Infisical(自己ホスト)は2026-08-29付けで完全に廃止した。現在の方針は次の通り。

#table(
  columns: (auto, 1fr, auto),
  stroke: 0.5pt + rgb("#c3ced9"),
  inset: 8pt,
  align: (left, left, left),
  table.header([*対象*], [*保管場所*], [*理由*]),
  [DB / pgAdmin / CORS 等(`app-env`)],
  [`manifest`リポジトリ直下の `prod.env` / `staging.env`(平文コミット)],
  [DBはClusterIP限定で外部到達不能],

  [GHCR pullトークン],
  [GitHub Environment Secret(`production-vps` / `test-vps`)],
  [CIからのみ必要],

  [Cloudflare Origin CA証明書],
  [GitHub Environment Secret(`production-vps`、環境限定)],
  [本番専用の機微情報],

  [Cloudflare Access クライアント資格情報],
  [GitHub Actions Secret(管理用SSH Tunnel専用)],
  [app-envとは無関係],

  [Grafana管理者パスワード等],
  [k8s Secret(`grafana-secrets`)、ブートストラップ時に手動投入],
  [gitignore対象、循環依存を避けるため],
)

`manifest`リポジトリのCIが`prod.env` / `staging.env`をVPSの`/home/github/app-env/`に
同期し、`2026kosensai`リポジトリのCIがそのパスを直接`--from-env-file`で参照する。
このため`manifest`側のCIが`2026kosensai`側より先に一度動いている必要がある。

= CI/CDパイプライン

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt + rgb("#c3ced9"),
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
    イメージbuild/push → GHCR pull token・Origin CA証明書をGitHub Secretsから取得 →
    `kubectl apply -k infra/k8s/overlays/prod`(backend/frontend/website個別に
    path-filter判定)→ rollout確認
  ],
  [`2026kosensai` → `test`],
  [同上(test namespace、pgAdmin用Cloudflare Accessは別途手動設定)],
)

いずれもGitHub ActionsからVPSへは、管理用のCloudflare Access Tunnel(`cloudflared access
tcp`)経由でSSH接続する。これは公開Web用のTunnel(namespace `network`のcloudflared)とは
別物で、VPS側からのoutbound接続であるため、§3のnftables allowlistとは無関係に動作する。

= 監視

Prometheus(namespace `monitoring`)は次をスクレイプする。

- `node-exporter`: ノードのCPU/メモリ/ディスク
- `traefik`: Traefik自身のメトリクス(現状9100番ポートが未公開のため要修正、既知の課題)
- `kube-state-metrics`: Pod/Deployment/StatefulSetのオブジェクト状態
  (Running/Restart回数/Readyレプリカ数)
- `kubernetes-apiservers`: kube-apiserverのリクエストレイテンシ・エラー率
- `kubelet` / `kubernetes-cadvisor`: ノード・Pod単位のリソース使用量

いずれも`kubernetes_sd_configs`によるin-cluster discoveryと、ServiceAccountトークン
(`/var/run/secrets/kubernetes.io/serviceaccount/`)による認証を使う標準的な構成。
GrafanaのPrometheus/Lokiデータソースは自動プロビジョニングしておらず、初回のみ手動追加が必要
(`http://prometheus:9090`, `http://loki:3100`、いずれも`monitoring` namespace内)。
ログはGrafana Alloy(DaemonSet、`k3s/alloy-logging.yaml`)が全namespaceのPodログをLokiへ出荷する。

= 障害と設計判断

== nftablesルールのインターフェーススコープ(2026-08-29)

Origin Authentication導入時に追加したnftablesルールが、当初`tcp dport 443`のみで
判定しており、送信元インターフェースを指定していなかった。クラスタ内部には
`kubernetes.default.svc`(ClusterIP、`10.43.0.1:443`)を含む複数のClusterIPが
たまたま443番を使っており、このルールはPod→APIサーバー間の内部通信まで
巻き込んでdropしてしまった。

結果として`helm-install-traefik`ジョブ(Traefikの新しいエントリーポイント設定を
適用するためのHelmインストール)がAPIサーバーに到達できず、
インストール失敗→アンインストール→再インストールのクラッシュループに陥り、
Traefik自体が消滅。本番環境が約1時間ダウンした(Cloudflareエラー521/526)。

*対処*: ルールを`iifname`(ノードの実際の外部NIC。ハードコードではなく
`ip route show default`から都度動的に解決)でスコープした。クラスタ内部の
トラフィックは定義上この物理インターフェースを通らないため、どのClusterIPが
443番を使っていても衝突しない。

同時に、Traefikのコンテナポート・Service公開ポートでも類似の衝突が発生していた
(`websecure-mtls`をchartのデフォルト`websecure`と同じ8443番/443番で定義していたため)。
コンテナポートは8444番、Service公開は`expose.default: false`(hostPortのみ、
Service経由の公開はそもそも不要)に変更して解消した。

= リファレンス

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt + rgb("#c3ced9"),
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
)
