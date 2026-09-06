# nara-kosensai/manifest

nara-kosensai(奈良高専祭)のインフラ設定リポジトリ。単一VPS上のシングルノードk3s
クラスタを、特定サービスに紐づかない共有プラットフォーム部分(cloudflared,
Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook, ArgoCD本体)について管理する。
外部通信は原則Cloudflare Tunnel経由のみで、実際のマニフェストapplyはArgoCD
(GitOps)が本リポジトリ・`2026kosensai`リポジトリをそれぞれ直接git pullして行う。

## ドキュメント

| ドキュメント | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | システム構成・ネットワーク/セキュリティ・シークレット管理・CI/CDパイプラインの仕様書。設計判断の記録もここ |
| [docs/operations.md](docs/operations.md) | 既知の障害と診断・対処手順(トラブルシュート用) |
| [docs/bootstrap.md](docs/bootstrap.md) | 新規VPSにゼロから構築する場合の一度きりの手動セットアップ手順 |

## リポジトリの役割分担

**設定は基本的にこの `manifest` リポジトリで管理する。** 特定のサービス(2026kosensaiアプリ)
に紐づく設定だけ、そのサービスのリポジトリに置く。

| リポジトリ | 内容 |
| --- | --- |
| `manifest`(このリポジトリ) | クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定(`k8s/`: cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook, kosensai-form-preview)、ArgoCD本体・Application定義、ドキュメント |
| `2026kosensai` | アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト(`infra/k8s/base/app`, `overlays/{prod,test}`)・CI/CD |
| `www` | 過去年度アーカイブの中身と、そのイメージをビルドするDockerfile/CI(デプロイ先マニフェストはこのリポジトリの`k8s/base/web-static`) |

新しく何かを追加するとき: そのアプリ/サービス固有の設定(env, リソース要求, その
サービスだけが使うDockerfile)は該当サービスのリポジトリへ。namespace定義・Ingress
ルーティング・cluster全体で共有するミドルウェアなど、特定サービスに閉じない設定は
ここ(`manifest`)へ置く。

## 構成

```
manifest/
  k3s/    # クラスタ自体のブートストラップ(k3sインストール時に1回、以後は変更時のみ再適用)
  k8s/    # 共有プラットフォームのマニフェスト(Kustomize)
    base/               # namespace横断で使う基礎マニフェスト
    overlays/shared/    # 上記をまとめたもの。ArgoCD(platform-shared Application)が直接pull
    bootstrap/argocd/   # ArgoCD本体のインストール(manifestのCIが恒久的にapply)
    argocd-apps/        # ArgoCDが管理するApplication定義(App-of-apps)
  docs/   # architecture.md / operations.md / bootstrap.md
  *.env   # 2026kosensaiアプリ用の環境変数(下記参照)
```

- `k3s/install.sh` — k3sインストール(`--disable=servicelb`)。
- `k3s/traefik-config.yaml` — Traefikの`service.type: ClusterIP`化(公開ポート非公開)。
- `k3s/alloy-logging.yaml` — Grafana AlloyのDaemonSet(全namespaceのPodログをLokiへ)。
- `k3s/local-path-retain-storageclass.yaml` — 消えて困るデータ用の`Retain`StorageClass。
- `k8s/base/ingress/security-headers.yaml` — 全namespace共通のセキュリティヘッダーMiddleware
  (2026kosensaiリポジトリにも同一内容を複製配置)。
- `k8s/base/web-static/` — 過去年度アーカイブ(`www-archive`) + storybook + form-preview。
- `k8s/base/network/` — cloudflared(公開Web用トンネル)。
- `k8s/base/monitoring/` — Loki, Grafana, Prometheus, node-exporter, kube-state-metrics。
- `k8s/bootstrap/argocd/` — ArgoCD本体のインストール(namespace, upstream install
  manifest, `argocd-cm`/`argocd-cmd-params-cm`/`argocd-notifications-cm`パッチ,
  `argocd.nara-kosensai.com`へのIngressRoute)。
- `k8s/argocd-apps/` — ArgoCDが管理するApplication定義(App-of-apps)。`root-app.yaml`
  だけを一度きり手動でapplyすれば、以降はこのディレクトリ自体もgit経由でArgoCDが管理する。

詳細な設計判断・namespace構成・ネットワーク経路は[docs/architecture.md](docs/architecture.md)
を参照。

## ArgoCD(GitOps)

- `manifest`(共有基盤)・`2026kosensai`(アプリ本体prod/test)いずれも、マニフェスト本体の
  applyはArgoCDがそれぞれのリポジトリを直接git pullして行う。各リポジトリのCIは
  「namespace作成・Secret投入(ArgoCDの管理対象外)」と、`2026kosensai`側では追加で
  「イメージbuild/push後、`kustomize edit set image`で書き換えたマニフェストのタグを
  gitにcommit&push」だけを行う。
- ArgoCD UIは`https://argocd.nara-kosensai.com`でCloudflare Tunnel + Access経由公開。
- デプロイ結果はArgoCD UIに加え、Teams(Power Automate webhook)にも通知される
  (`k8s/bootstrap/argocd/argocd-notifications-cm-patch.yaml`)。
- 各Applicationの定義は`k8s/argocd-apps/`を参照。

**新しいApplicationやリポジトリを追加する場合の注意**：Applicationは初回、
`syncPolicy.automated`を付けずに(手動sync)作成し、`argocd app diff <name>`で
「差分なし」であることを確認してから`automated`(prune+selfHeal)に変更すること。
既に本番で稼働中のリソースに対して、gitとの差分がある状態でいきなり自動syncを
有効にすると意図しないロールバック/再作成が起きうる。

## app-env(2026kosensaiアプリの環境変数)

`prod.env` / `staging.env` / `dev.env` / `backend-dev.env` は2026kosensaiアプリ
(backend/frontend/website/pgadmin)の環境変数。DBはk8s ClusterIP内に閉じており外部
到達不能なため、このリポジトリで平文コミットを許容している。

| ファイル | 用途 |
| --- | --- |
| `prod.env` | `2026kosensai`の`prod` namespace(`app-env` Secret) |
| `staging.env` | `2026kosensai`の`test` namespace(`app-env` Secret) |
| `dev.env` / `backend-dev.env` | ローカル開発用(docker-compose等)。VPSには同期しない |

このリポジトリのCI(`deploy.yml`)が`prod.env`/`staging.env`をVPSの
`/home/github/app-env/{prod,staging}.env`に同期し、2026kosensaiリポジトリの
`deploy-prod.yml`/`deploy-test.yml`がそのパスを直接`--from-env-file`で使う
(2026kosensai側のCIより先に、このリポジトリのCIが一度動いている必要がある)。

`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET`はここには含めない
(GitHub Actions Secretとして2026kosensai側で別途管理)。

## ローカルでの動作確認

```sh
kubectl kustomize k8s/overlays/shared      # レンダリング確認
kubectl apply --dry-run=server -k k8s/overlays/shared
kubectl kustomize k8s/bootstrap/argocd     # ArgoCD自体のレンダリング確認
```

新しいVPSでゼロから構築する手順は[docs/bootstrap.md](docs/bootstrap.md)を参照。
