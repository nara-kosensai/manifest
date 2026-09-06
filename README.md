# nara-kosensai k3s移行 手順書

VPSネイティブのnginx + 複数docker-compose(このリポジトリの `nginx.conf` /
`default.conf` / `grafana/` が旧構成)で運用していたシステムを、
同一VPS上のシングルノードk3sに全面移行する。外部通信は原則Cloudflare Tunnel経由のみとし、
クラスタはノードの公開インターフェースに極力ポートをバインドしない
(唯一の例外が本番アプリ向けのOrigin Authentication、詳細は後述)。

## リポジトリの役割分担

**設定は基本的にこの `config` リポジトリで管理する。** 特定のサービス(2026kosensaiアプリ)
に紐づく設定だけ、そのサービスのリポジトリに置く。

| リポジトリ | 内容 |
| --- | --- |
| `config`(このリポジトリ) | クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定(`k8s/`: cloudflared, Grafana/Loki/Prometheus, 過去年度アーカイブ, storybook, kosensai-form-preview)、この手順書 |
| `2026kosensai` | アプリ本体(backend/frontend/db/pgadmin/website)のDockerfile・k8sマニフェスト(`infra/k8s/base/app`, `overlays/{prod,test}`)・CI/CD |
| `www` | 過去年度アーカイブの中身と、そのイメージをビルドするDockerfile/CI(デプロイ先マニフェストはこのリポジトリの`k8s/base/web-static`) |

新しく何かを追加するとき: そのアプリ/サービス固有の設定(env, リソース要求, その
サービスだけが使うDockerfile)は該当サービスのリポジトリへ。namespace定義・Ingress
ルーティング・cluster全体で共有するミドルウェアなど、特定サービスに閉じない設定は
ここ(`config`)へ置く。

## 構成

```
config/
  k3s/    # クラスタ自体のブートストラップ(k3sインストール時に1回、以後は変更時のみ再適用)
  k8s/    # 共有プラットフォームのマニフェスト(Kustomize、configのCIが継続的にapply)
  nginx.conf, default.conf, grafana/, infisical/   # 旧構成(退役、下記の対応表を参照。
                                                    # infisical/はInfisical自体を
                                                    # 廃止したため参考資料としてのみ残る)
```

- `k3s/install.sh` — k3sインストール(`--disable=servicelb`)。
- `k3s/traefik-config.yaml` — Traefikの`service.type: ClusterIP`化(公開ポート非公開)。
- `k3s/alloy-logging.yaml` — Grafana AlloyのDaemonSet(全namespaceのPodログをLokiへ)。
- `k3s/local-path-retain-storageclass.yaml` — 消えて困るデータ用の`Retain`StorageClass。
- `k8s/base/ingress/security-headers.yaml` — 全namespace共通のセキュリティヘッダーMiddleware
  (2026kosensaiリポジトリにも同一内容を複製配置、単純にファイル管理を分けるため)。
  なお`prod`/`test`のIngressRouteは`web-static`namespaceのServiceをcross-namespaceで
  直接参照する。このクラスタは単一テナント運用のため、Traefikの
  `providers.kubernetesCRD.allowCrossNamespace: true`(`k3s/traefik-config.yaml`)を
  有効にしている(namespace分離バイパス系の脆弱性はマルチテナント環境でのみ意味を持つ)。
- `k8s/base/web-static/` — 過去年度アーカイブ(`www-archive`) + storybook + form-preview。
- `k8s/base/network/` — cloudflared(公開Web用トンネル)。
- `k8s/base/monitoring/` — Loki, Grafana, Prometheus, node-exporter,
  kube-state-metrics。PrometheusはServiceAccountトークンで認証し
  (`prometheus-rbac.yaml`)、node-exporter/Traefik/kube-state-metricsに加えて
  kube-apiserver・kubelet・cAdvisor(`kubernetes_sd_configs`によるnode discovery)
  もスクレイプする。Grafanaのdatasource(Prometheus/Loki)は自動プロビジョニング
  していないため、初回は手動で追加が必要
  (`http://prometheus:9090`, `http://loki:3100`、いずれも`monitoring` namespace内)。
- `k8s/overlays/shared/` — 上記すべてを対応するnamespaceにまとめて適用する。
  実際のapplyはこのリポジトリのCIではなくArgoCD(`platform-shared` Application)が
  gitから直接pullして行う(下記「ArgoCD(GitOps)」節を参照)。
- `k8s/bootstrap/argocd/` — ArgoCD本体のインストール(namespace, upstream install
  manifest, `argocd-cm`/`argocd-cmd-params-cm`パッチ, `argocd.nara-kosensai.com`への
  IngressRoute)。`k3s/`同様、ArgoCDに委譲せずこのリポジトリのCIが恒久的に適用する
  (ArgoCDが壊れた場合にArgoCD自身では直せなくなるchicken-and-egg問題を避けるため)。
- `k8s/argocd-apps/` — ArgoCDが管理するApplication定義(App-of-apps)。`root-app.yaml`
  だけを一度きり手動でapplyすれば、以降はこのディレクトリ自体もgit経由でArgoCDが
  管理する。

## ArgoCD(GitOps)

2026年9月にpush型CI(`kubectl apply`)からArgoCDによるpull型GitOpsへ移行した。

- `config`(共有基盤)・`2026kosensai`(アプリ本体prod/test)いずれも、マニフェスト本体の
  applyはArgoCDがそれぞれのリポジトリを直接git pullして行う。
- 各リポジトリのCIは「namespace作成・Secret投入(ArgoCDの管理対象外)」と、
  `2026kosensai`側では追加で「イメージbuild/push後、`kustomize edit set image`で
  書き換えたマニフェストのタグをgitにcommit&push」だけを行う。`kubectl apply`や
  `rollout status`待ちはCIから削除済み(ArgoCDのUI/通知で確認する)。
- ArgoCD UIは`https://argocd.nara-kosensai.com`でCloudflare Tunnel + Access経由公開。
- 各Applicationの定義は`k8s/argocd-apps/`を参照。

**新しいApplicationやリポジトリを追加する場合の注意**：Applicationは初回、
`syncPolicy.automated`を付けずに(手動sync)作成し、`argocd app diff <name>`で
「差分なし」であることを確認してから`automated`(prune+selfHeal)に変更すること。
既に本番で稼働中のリソースに対して、gitとの差分がある状態でいきなり自動syncを
有効にすると意図しないロールバック/再作成が起きうる。

## namespace

| namespace | 内容 | マニフェストの出所 | 管理元 |
| --- | --- | --- | --- |
| `prod` / `test` | 2026kosensaiアプリ本体 | `2026kosensai`リポジトリ | ArgoCD(`app-*`/`website-*`/`ingress-*` Application) |
| `web-static` | 過去年度アーカイブ, storybook, form-preview(singleton) | `config`リポジトリ | ArgoCD(`platform-shared` Application) |
| `network` | cloudflared(singleton) | `config`リポジトリ | ArgoCD(`platform-shared` Application) |
| `monitoring` | Loki, Grafana, Prometheus, node-exporter | `config`リポジトリ | ArgoCD(`platform-shared` Application) |
| `pgadmin` | pgAdmin(prod/test DB共通の1インスタンス) | `config`リポジトリ | ArgoCD(`platform-shared` Application) |
| `argocd` | ArgoCD本体(GitOpsコントローラ) | `config`リポジトリ(`k8s/bootstrap/argocd/`) | `config`のCI(push-CI、恒久) |
| `kube-system` | k3s同梱Traefik(ClusterIPのみ、公開ポートなし) | `config`リポジトリ(`k3s/`) | `k3s/`ブートストラップ(push-CI、恒久) |

namespace自体の作成・ArgoCDの管理対象外のSecret(app-env/ghcr-pull/grafana-secrets/
pgadmin-secrets/cloudflared-credentials/cloudflare-origin-cert/
argocd-notifications-secret)の投入は、引き続き各リポジトリのCIが
(pgadmin-secrets/argocd-notifications-secretのみ手動で)SSH経由で行う。

過去にInfisicalを`infisical` namespaceで運用していたが廃止した(秘密情報は
下記の通り`app-env`のgitコミットとGitHub Secretsに移行した)。VPS上に
namespaceが残っている場合は手動で削除が必要
(`kubectl delete namespace infisical` — Infisical自身のPostgres/Redisの
データも消えるため、必要な情報がないか確認してから実行すること)。

## app-env(2026kosensaiアプリの環境変数)

`prod.env` / `staging.env` / `dev.env` / `backend-dev.env` は2026kosensaiアプリ
(backend/frontend/website/pgadmin)の環境変数。Infisicalは経由せずこのリポジトリで
直接管理する(DBはk8s ClusterIP内に閉じており外部到達不能なため、平文コミットを
許容する判断)。

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

## Origin Authentication (mTLS) — 本番アプリのみ

`nara-kosensai.com` / `www.nara-kosensai.com`(2026kosensaiリポジトリの`prod`
namespace)だけは、Cloudflare Tunnelを使わずCloudflareの
**Origin Authentication(Authenticated Origin Pulls, mTLS)** で直接オリジンに
到達させる。`test.nara-kosensai.com`および`storybook`/`grafana`/`pgadmin*`/
`info-check`は従来通りTunnel経由(pgadminはCloudflare Accessでの認証も継続)。

### 仕組み

- `k3s/traefik-config.yaml` に `websecure-mtls` エントリーポイントを追加し、
  コンテナの8444番(デフォルトの`websecure`エントリーポイントが使う8443番との
  衝突を避けるため)を `hostPort: 443` でノードの公開インターフェースに直接bind
  している。`expose.default: false` にしてService(ClusterIP)には追加しない
  (hostPortはkube-proxyを経由しないため不要。追加すると`websecure`の
  デフォルトの443番公開と重複しHelmインストールが失敗する)。Service自体は
  引き続きClusterIPなので、Tunnel専用の`web`(80番)は非公開のまま。
- `k8s/base/network/cloudflare-aop-ca.yaml` に、Cloudflareが公開している
  Authenticated Origin Pulls用CA証明書
  (`https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem`)
  を配置(秘密情報ではないためgit管理)。
- `k8s/base/network/cloudflare-mtls-tlsoption.yaml`(Traefik `TLSOption` CRD)が
  そのCAでCloudflareからのクライアント証明書を検証する
  (`clientAuthType: RequireAndVerifyClientCert`)。
- 2026kosensaiリポジトリの `infra/k8s/overlays/prod/ingress/ingressroute.yaml`
  が `websecure-mtls` エントリーポイントとこの`TLSOption`を参照し
  (namespace跨ぎ参照。`allowCrossNamespace: true`で許可済み)、Cloudflareが
  発行したOrigin CA証明書(オリジンサーバ側のTLS証明書、`prod` namespaceの
  Secret、GitHub Environment Secret経由でCIが投入)をサーバ証明書として使う。
- `test`やその他のIngressRouteは`web`エントリーポイントのみを使うため、
  `websecure-mtls`(443番)からは物理的にルーティングされない
  (Traefikはエントリーポイント単位でルーターをbindするため)。

### Cloudflareダッシュボード側の設定(一度きり、手動)

1. `SSL/TLS > Origin Server > Create Certificate` でOrigin CA証明書
   (`nara-kosensai.com`, `www.nara-kosensai.com`をカバー)を発行し、
   cert/keyを2026kosensaiリポジトリの`production-vps` environmentの
   GitHub Environment Secretに `CF_ORIGIN_CERT` / `CF_ORIGIN_KEY` として登録する
   (prod専用の機微情報のためrepository全体のSecretではなくenvironment scopeにする)。
2. `SSL/TLS > Origin Server > Authenticated Origin Pulls` を有効化
   (zone-level。Freeプランのためper-hostnameのカスタムクライアント証明書は
   使えないが、zone-levelのCloudflare管理証明書で十分)。
3. `SSL/TLS > Overview` を `Full (strict)` に変更
   (Tunnel経由のホストはこの設定と無関係に動作し続けるため影響なし)。
4. `k3s/cloudflare-ip-allowlist.sh`(+ `.service`/`.timer`)が、443/tcp宛の
   パケットをCloudflareの公開IPレンジ以外はnftablesのraw prerouting段階で
   silent DROPする(TCP/TLSレベルで一切応答を返さない。mTLS検証はその内側の
   保険という位置付け)。`install.sh`が初回導入・有効化し、以後は
   `deploy.yml`が更新の都度再適用、systemd timerがIPレンジを日次で自動更新する。
   既存のk3s/kube-proxyが使うnftables/iptablesルールには触れない専用テーブル
   構成。**このスクリプトはnftablesを前提とする**(ufuやiptables-legacyのみの
   環境では動作しない)。
5. 動作確認後、`nara-kosensai.com` / `www.nara-kosensai.com` のDNSレコードを
   Tunnel向けCNAME(`<tunnel-id>.cfargotunnel.com`)から、VPSの公開IPを指す
   A(/AAAA)レコード(Proxied継続)に切り替える。
6. 切り替え後、`k8s/base/network/cloudflared-configmap.yaml` の`ingress`から
   `nara-kosensai.com` / `www.nara-kosensai.com` のエントリを削除してよい
   (test/admin系は残す)。

## 旧nginx設定との対応関係

| 旧 (`default.conf`) | 新 |
| --- | --- |
| http-context の `add_header` (CSP等) | `k8s/base/ingress/security-headers.yaml` |
| www→apex, `/`, `/2026`, `/2026/app` リダイレクト | `2026kosensai/infra/k8s/overlays/{prod,test}/ingress/redirects.yaml` |
| 旧年度(2009-2016,2021)の外部リダイレクト | 同上(prodのみ) |
| `/2026/app/` → `proxy_pass localhost:3000` | `2026kosensai`側 IngressRoute(frontend Service) |
| `/2026/` → `alias .../website/dist/` | 同上(website Service, CIビルドのnginxイメージ) |
| `root /var/www/html/`(過去年度アーカイブ) | `k8s/base/web-static/archive-*.yaml` |
| `/404.html` alias | `2026kosensai`側 errors Middleware(`web-static`のwww-archiveを参照) |
| storybookサーバブロック | `k8s/overlays/shared/web-static/storybook-route.yaml` |
| `:8080 /metrics` (nginx stub_status) | Traefikの標準Prometheusメトリクス |
| `grafana/docker-compose.yml`(Loki, Grafana, Prometheus, node-exporter, promtail, nginx-exporter) | `k8s/base/monitoring/*`。**promtailとnginx-exporterはnginx retireに伴い廃止**(promtailの役割はGrafana Alloyに、nginx-exporterの役割はTraefikネイティブメトリクスに統合) |
| `infisical/docker-compose.prod.yml` | 廃止(下記「app-env」節の通り、秘密情報はgitコミットとGitHub Secretsに移行) |

## 一度きりの手動ブートストラップ手順

コードで完全に再現できない箇所(秘密情報の性質、または初回のみの操作):

1. **VPSにk3sをインストール**: `k3s/install.sh` をVPS上で実行する(root権限が
   必要だが、非rootで呼んでもスクリプト自身が自動的に`sudo`へ昇格する)。
   ```
   ./k3s/install.sh
   ```
   k3s本体のインストールに加えて、`traefik-config.yaml` / `alloy-logging.yaml` /
   `local-path-retain-storageclass.yaml` を `/var/lib/rancher/k3s/server/manifests/`
   に配置するところまでこのスクリプトが自動で行う(追加のコマンドは不要)。
   以後これらのファイルを更新した場合は、`config`リポジトリへのpushでCIが
   sudo経由で再配置する(`.github/workflows/deploy.yml`)。
2. **Cloudflare Tunnel(公開Web用)を新規作成**: 既存のSSH管理用Cloudflare Access
   トンネルとは別物。
   ```
   cloudflared tunnel create nara-kosensai-web
   cloudflared tunnel route dns nara-kosensai-web nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web www.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web test.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web storybook.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web pgadmin.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web pgadmin-test.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web grafana.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web info-check.nara-kosensai.com
   cloudflared tunnel route dns nara-kosensai-web argocd.nara-kosensai.com
   ```
   生成される `credentials.json` を、VPS上で直接k8s Secretとして投入する:
   ```
   kubectl create namespace network
   kubectl -n network create secret generic cloudflared-credentials \
     --from-file=credentials.json=./credentials.json
   ```
3. **pgAdmin用Cloudflare Accessポリシー**: `pgadmin*.nara-kosensai.com` に対して
   Cloudflareダッシュボード側でAccessアプリケーション(認証ポリシー)を設定する。
4. **Grafanaの秘密情報を投入**(`grafana/docker-compose.yml` は `.gitignore`済み、
   埋め込まれていた `GF_SECURITY_ADMIN_PASSWORD` と `GF_AUTH_GITHUB_CLIENT_SECRET` を使う):
   ```
   kubectl create namespace monitoring
   kubectl -n monitoring create secret generic grafana-secrets \
     --from-literal=admin-password='<GF_SECURITY_ADMIN_PASSWORD>' \
     --from-literal=github-client-secret='<GF_AUTH_GITHUB_CLIENT_SECRET>'
   ```
5. **pgAdminの秘密情報を投入**(prod/test共通の1インスタンスに統合済み。値は旧
   `2026kosensai`リポジトリの`prod.env`/`staging.env`にあった
   `PGADMIN_DEFAULT_EMAIL`/`PGADMIN_DEFAULT_PASSWORD`と同じもので構わない):
   ```
   kubectl create namespace pgadmin
   kubectl -n pgadmin create secret generic pgadmin-secrets \
     --from-literal=default-email='<PGADMIN_DEFAULT_EMAIL>' \
     --from-literal=default-password='<PGADMIN_DEFAULT_PASSWORD>'
   ```
6. **GHCR pull用PAT**(`web-static` namespaceのwww-archive/storybookイメージがPrivateなため):
   ```
   kubectl create namespace web-static
   kubectl -n web-static create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io --docker-username=<github-username> \
     --docker-password=<read:packages スコープのPAT>
   ```
7. **`config`リポジトリのGitHub Actions環境(`production-vps`)にSSH関連シークレットを設定**:
   `SSH_PRIVATE_KEY` / `SSH_USER` / `SSH_HOST` / `CLOUDFLARED_CLIENT_ID` /
   `CLOUDFLARED_CLIENT_SECRET`(値は2026kosensaiリポジトリのものと同じでよい、
   SSH管理用Cloudflare Accessトンネル経由でVPSに入るため)。**`SSH_USER`はVPS上のCI専用
   アカウント(例: `github`)を指し、対話ログインで使う`admin`アカウントとは別物**。この
   `SSH_USER`のホームディレクトリ(`/home/<SSH_USER>`)には自由に書き込めること、また
   `/var/lib/rancher/k3s/server/manifests/` へのパスワードなし`sudo`を実行できることが必要。
8. **2026kosensaiリポジトリの`production-vps`/`test-vps` environmentに
   `GHCR_PULL_TOKEN`(read:packages スコープのPAT)をGitHub Environment Secretとして
   追加**(prod/test namespace用のimagePullSecret。Infisicalは経由しない)。
9. **ArgoCD自体をインストール**: 手順1〜8を終えた状態で`config`リポジトリの`main`への
   pushでCIが`k8s/bootstrap/argocd`を適用し、ArgoCD本体が立ち上がる
   (`kubectl -n argocd get pods`で確認)。
9. **GitHubリポジトリへの読み取り用SSH Deploy Keyを発行**: `config`(`nara-kosensai/manifest`)
   と`2026kosensai`それぞれのリポジトリ設定 `Settings > Deploy keys` で読み取り専用
   (Write access不要)のDeploy Keyを追加し、対応する秘密鍵をArgoCDに登録する:
   ```
   kubectl -n argocd create secret generic manifest-repo \
     --from-literal=type=git \
     --from-literal=url=git@github.com:nara-kosensai/manifest.git \
     --from-file=sshPrivateKey=<manifest用秘密鍵のパス>
   kubectl -n argocd label secret manifest-repo argocd.argoproj.io/secret-type=repository

   kubectl -n argocd create secret generic 2026kosensai-repo \
     --from-literal=type=git \
     --from-literal=url=git@github.com:fumikun/2026kosensai.git \
     --from-file=sshPrivateKey=<2026kosensai用秘密鍵のパス>
   kubectl -n argocd label secret 2026kosensai-repo argocd.argoproj.io/secret-type=repository
   ```
10. **ArgoCDのApp-of-appsをブートストラップ**: `root-app.yaml`だけを一度きり手動でapplyする
    (以降はこのファイル自体もgit経由でArgoCDが管理する)。
    ```
    kubectl apply -f k8s/argocd-apps/root-app.yaml
    ```
    続けて`platform-shared`をはじめ各Applicationが`argocd`namespaceに現れる
    (`kubectl -n argocd get applications`)。**本番影響を避けるため、`kubectl apply`直後は
    各Applicationで`argocd app diff <name>`を実行し、gitとVPS上の実際の状態に差分がないことを
    確認してから運用を続けること**(差分がある場合、意図しないリソースの再作成/削除が
    起きうる)。
11. **ArgoCD UI用のCloudflare Accessポリシー**: `argocd.nara-kosensai.com`に対して
    Cloudflareダッシュボード側でAccessアプリケーション(認証ポリシー、pgAdminと同様の設定)を
    追加する。ArgoCDの初期adminパスワードは`kubectl -n argocd get secret
    argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`で取得できる
    (初回ログイン後、ローテーション/削除を推奨)。
12. **Teams通知用webhook URLを投入**(`argocd-notifications-cm-patch.yaml`が参照する
    `$teams-webhook-url`の実体。Power Automateフローの署名付きURLで機微情報のため
    git管理しない):
    ```
    kubectl -n argocd create secret generic argocd-notifications-secret \
      --from-literal=teams-webhook-url='<Power AutomateフローのHTTPトリガーURL>'
    ```
    (Secretを更新した場合は`kubectl -n argocd rollout restart
    deployment/argocd-notifications-controller`で反映する)。

これ以降、共有プラットフォーム設定は `config` への push (`main`ブランチ) で、
アプリ本体は `2026kosensai` の `prod`/`test` ブランチへのpushで、それぞれ独立に
コードから再現・更新される。ただし実際のマニフェストapplyはArgoCDが担うため、
CIのpush自体はgitの内容を更新するだけであり、反映確認はArgoCD UI/CLIで行う。

## 動作確認

```sh
kubectl kustomize k8s/overlays/shared      # レンダリング確認
kubectl apply --dry-run=server -k k8s/overlays/shared
kubectl kustomize k8s/bootstrap/argocd     # ArgoCD自体のレンダリング確認
```

適用後:
- `kubectl get svc -n kube-system traefik` で `TYPE=ClusterIP` になっていること
  (公開ポートを一切bindしていないこと)。
- `curl -I https://grafana.nara-kosensai.com/`, `https://storybook.nara-kosensai.com/`,
  `https://argocd.nara-kosensai.com/`(Cloudflare Access認証後)が200/302で応答すること。
- `kubectl -n argocd get applications` で全Applicationが`Sync Status: Synced`,
  `Health: Healthy`になっていること。
- GrafanaでLoki/Prometheusのデータソードが有効で、各namespaceのPodログ・
  node-exporter/Traefikメトリクスが見えること。
- `nft list table ip cloudflare_mtls` / `nft list table ip6 cloudflare_mtls6`
  でCloudflareのIPレンジが入ったsetが存在すること。VPS外の任意のIPから
  `curl -v https://<VPSの公開IP>:443 -H "Host: nara-kosensai.com"` を実行し、
  TCP接続自体がタイムアウトする(応答が一切返らない)ことを確認する。
