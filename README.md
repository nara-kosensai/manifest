# nara-kosensai/manifest

nara-kosensai(奈良高専祭)のインフラ設定リポジトリ。単一VPS上のシングルノードk3s
クラスタの**全k8sマニフェスト**(クラスタブートストラップ、共有プラットフォーム設定、
アプリ本体、website)をこの1リポジトリに集約している。外部通信は原則Cloudflare Tunnel
経由のみで、実際のマニフェストapplyはArgoCD(GitOps)が本リポジトリを直接git pullして行う。

ディレクトリ構造は[traPtitech/manifest](https://github.com/traPtitech/manifest)を参考に、
サービス単位でトップレベルディレクトリを分ける構成にしている(Kustomizeの
base/overlaysによる階層化はせず、各ディレクトリが単体で`kubectl kustomize <dir>`
可能な完結したマニフェストセットになっている)。

## ドキュメント

| ドキュメント | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | システム構成・ネットワーク/セキュリティ・シークレット管理・CI/CDパイプラインの仕様書。設計判断の記録もここ |
| [docs/operations.md](docs/operations.md) | 既知の障害と診断・対処手順(トラブルシュート用) |
| [docs/bootstrap.md](docs/bootstrap.md) | 新規VPSにゼロから構築する場合の一度きりの手動セットアップ手順 |

## リポジトリの役割分担

**k8sマニフェストはすべてこの`manifest`リポジトリに集約する。** 他のリポジトリは
イメージのビルド・pushと、このリポジトリへのマニフェスト更新(イメージタグ書き換え)
commit&pushだけを行う。

| リポジトリ | 内容 |
| --- | --- |
| `manifest`(このリポジトリ) | 全k8sマニフェスト(クラスタブートストラップ`k3s/`、ArgoCD本体`argocd/`、Application定義`applications/`、共有プラットフォーム設定、アプリ本体、website)、ドキュメント |
| `2026kosensai` | アプリ本体(backend/frontend/db/website)のDockerfile・CI。CIはイメージをbuild/pushした後、本リポジトリの`app-{prod,test}/`・`website-{prod,test}/`配下の`kustomization.yaml`を`kustomize edit set image`で書き換えてcommit&pushする |
| `www` | 過去年度アーカイブの中身と、そのイメージをビルドするDockerfile/CI(デプロイ先マニフェストは本リポジトリの`web-static/`) |

新しく何かを追加するとき: そのアプリ/サービス固有のコード(Dockerfile、アプリの
ソース)は該当サービスのリポジトリへ。k8sマニフェスト(Deployment/Service/
IngressRoute/namespace定義等)はすべてこの`manifest`リポジトリへ置く。

## 構成

```
manifest/
  k3s/            # クラスタ自体のブートストラップ(k3sインストール時に1回、以後は変更時のみ再適用)
  argocd/         # ArgoCD本体のインストール(manifestのCIが恒久的にapply)
  applications/   # ArgoCDが管理するApplication定義(App-of-apps)
  network/        # cloudflared(公開Web用Tunnel)
  monitoring/     # Grafana, Loki, Prometheus, node-exporter, kube-state-metrics
  pgadmin/        # prod/test共通の統合pgAdminインスタンス
  web-static/     # 過去年度アーカイブ(www-archive) + storybook + kosensai-form-preview
  app-prod/       # アプリ本体(backend/frontend/db)prod環境
  app-test/       # アプリ本体(backend/frontend/db)test環境
  website-prod/   # website prod環境
  website-test/   # website test環境
  ingress/        # 全namespace共通のセキュリティヘッダーMiddleware(security-headers)
  docs/           # architecture.md / operations.md / bootstrap.md
  *.env           # アプリ用の環境変数(下記参照)
```

各サービスディレクトリはそれぞれ独立した`kustomization.yaml`を持ち、単体で
`kubectl kustomize <dir>`できる(traPの`manifest`と同様、階層化されたbase/overlaysは
使わない)。namespaceが異なる複数のリソース群をまとめて扱う必要がある場合のみ、
ディレクトリ内で`namespace.yaml`を含めて定義する。

- `k3s/install.sh` — k3sインストール(`--disable=servicelb`)。
- `k3s/traefik-config.yaml` — Traefikの`service.type: ClusterIP`化(公開ポート非公開)。
- `k3s/alloy-logging.yaml` — Grafana AlloyのDaemonSet(全namespaceのPodログをLokiへ)。
- `k3s/local-path-retain-storageclass.yaml` — 消えて困るデータ用の`Retain`StorageClass。
- `ingress/security-headers.yaml` — 全namespace共通のセキュリティヘッダーMiddleware。
- `argocd/` — ArgoCD本体のインストール(namespace, upstream install
  manifest, `argocd-cm`/`argocd-cmd-params-cm`/`argocd-notifications-cm`パッチ,
  `argocd.nara-kosensai.com`へのIngressRoute)。
- `applications/` — ArgoCDが管理するApplication定義(App-of-apps)。`root-app.yaml`
  だけを一度きり手動でapplyすれば、以降はこのディレクトリ自体もgit経由でArgoCDが管理する。
- `app-prod/`・`app-test/` — backend/frontend/db(StatefulSet)と、そのnamespace(prod/test)
  全体のIngressRoute/Middleware(旧nginxルーティングの移植、
  [docs/architecture.md](docs/architecture.md)参照)。
- `website-prod/`・`website-test/` — Astro製website(`app-{prod,test}/`と同じnamespaceに
  デプロイされるが、イメージタグ更新のタイミングが異なるため別Application)。

詳細な設計判断・namespace構成・ネットワーク経路は[docs/architecture.md](docs/architecture.md)
を参照。

## ArgoCD(GitOps)

- マニフェスト本体のapplyはArgoCDがこの`manifest`リポジトリを直接git pullして行う。
  `manifest`・`2026kosensai`・`www`各リポジトリのCIは「namespace作成・Secret投入
  (ArgoCDの管理対象外)」と、`2026kosensai`/`www`側では追加で「イメージbuild/push後、
  `kustomize edit set image`で書き換えたマニフェストのタグをこの`manifest`リポジトリに
  commit&push」だけを行う。
- ArgoCD UIは`https://argocd.nara-kosensai.com`でCloudflare Tunnel + Access経由公開。
- デプロイ結果はArgoCD UIに加え、Teams(Power Automate webhook)にも通知される
  (`argocd/argocd-notifications-cm-patch.yaml`)。
- 各Applicationの定義は`applications/`を参照。

**新しいApplicationやリポジトリを追加する場合の注意**：Applicationは初回、
`syncPolicy.automated`を付けずに(手動sync)作成し、`argocd app diff <name>`で
「差分なし」であることを確認してから`automated`(prune+selfHeal)に変更すること。
既に本番で稼働中のリソースに対して、gitとの差分がある状態でいきなり自動syncを
有効にすると意図しないロールバック/再作成が起きうる。

## app-env(アプリの環境変数)

`prod.env` / `staging.env` / `dev.env` / `backend-dev.env` はアプリ本体
(backend/frontend/website/pgadmin)の環境変数。DBはk8s ClusterIP内に閉じており外部
到達不能なため、このリポジトリで平文コミットを許容している。

| ファイル | 用途 |
| --- | --- |
| `prod.env` | `prod` namespace(`app-env` Secret) |
| `staging.env` | `test` namespace(`app-env` Secret) |
| `dev.env` / `backend-dev.env` | ローカル開発用(docker-compose等)。VPSには同期しない |

このリポジトリのCI(`deploy.yml`)が`prod.env`/`staging.env`をVPSの
`/home/github/app-env/{prod,staging}.env`に同期し、`2026kosensai`リポジトリのCIが
そのパスを直接`--from-env-file`で使う(2026kosensai側のCIより先に、このリポジトリの
CIが一度動いている必要がある)。

`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET`はここには含めない
(GitHub Actions Secretとして`2026kosensai`側で別途管理)。

Infisical(自己ホスト)は完全に廃止済み。シークレット管理の詳細は
[docs/architecture.md#シークレット管理](docs/architecture.md#シークレット管理)を参照。

## ローカルでの動作確認

```sh
for dir in network monitoring pgadmin web-static app-prod app-test website-prod website-test; do
  kubectl kustomize "$dir"                       # レンダリング確認
  kubectl apply --dry-run=server -k "$dir"
done
kubectl kustomize argocd     # ArgoCD自体のレンダリング確認
```

新しいVPSでゼロから構築する手順は[docs/bootstrap.md](docs/bootstrap.md)を参照。
