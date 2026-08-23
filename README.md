# nara-kosensai k3s移行 手順書

VPSネイティブのnginx + 複数docker-compose(このリポジトリの `nginx.conf` /
`default.conf` / `grafana/` / `infisical/` が旧構成)で運用していたシステムを、
同一VPS上のシングルノードk3sに全面移行する。外部通信はCloudflare Tunnel経由のみとし、
クラスタはノードの公開インターフェースに一切ポートをバインドしない。

## リポジトリの役割分担

**設定は基本的にこの `config` リポジトリで管理する。** 特定のサービス(2026kosensaiアプリ)
に紐づく設定だけ、そのサービスのリポジトリに置く。

| リポジトリ | 内容 |
| --- | --- |
| `config`(このリポジトリ) | クラスタブートストラップ(`k3s/`)、特定サービスに紐づかない共有プラットフォーム設定(`k8s/`: cloudflared, Grafana/Loki/Prometheus, Infisical, 過去年度アーカイブ, storybook)、この手順書 |
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
  nginx.conf, default.conf, grafana/, infisical/   # 旧構成(退役、下記の対応表を参照)
```

- `k3s/install.sh` — k3sインストール(`--disable=servicelb`)。
- `k3s/traefik-config.yaml` — Traefikの`service.type: ClusterIP`化(公開ポート非公開)。
- `k3s/alloy-logging.yaml` — Grafana AlloyのDaemonSet(全namespaceのPodログをLokiへ)。
- `k3s/local-path-retain-storageclass.yaml` — 消えて困るデータ用の`Retain`StorageClass。
- `k8s/base/ingress/security-headers.yaml` — 全namespace共通のセキュリティヘッダーMiddleware
  (2026kosensaiリポジトリにも同一内容を複製配置。cross-namespace Middleware参照は
  Traefikの既知の脆弱性(namespace分離バイパス)を避けるため使わない設計)。
- `k8s/base/web-static/` — 過去年度アーカイブ(`www-archive`)+ storybook。
- `k8s/base/network/` — cloudflared(公開Web用トンネル)。
- `k8s/base/monitoring/` — Loki, Grafana, Prometheus, node-exporter。
- `k8s/base/infisical/` — Infisical本体(backend/redis/db)。
- `k8s/overlays/shared/` — 上記すべてを対応するnamespaceにまとめて適用する。

## namespace

| namespace | 内容 | 管理元 |
| --- | --- | --- |
| `prod` / `test` | 2026kosensaiアプリ本体 | `2026kosensai`リポジトリのCI |
| `web-static` | 過去年度アーカイブ, storybook(singleton) | `config`のCI |
| `network` | cloudflared(singleton) | `config`のCI |
| `monitoring` | Loki, Grafana, Prometheus, node-exporter | `config`のCI |
| `infisical` | Infisical本体 | `config`のCI |
| `kube-system` | k3s同梱Traefik(ClusterIPのみ、公開ポートなし) | `k3s/`ブートストラップ |

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
| `infisical/docker-compose.prod.yml` | `k8s/base/infisical/*` |

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
   cloudflared tunnel route dns nara-kosensai-web infisical.nara-kosensai.com
   ```
   生成される `credentials.json` を、VPS上で直接k8s Secretとして投入する
   (Infisical自身がまだ動いていないため、Infisicalを経由できない):
   ```
   kubectl create namespace network
   kubectl -n network create secret generic cloudflared-credentials \
     --from-file=credentials.json=./credentials.json
   ```
3. **pgAdmin用Cloudflare Accessポリシー**: `pgadmin*.nara-kosensai.com` に対して
   Cloudflareダッシュボード側でAccessアプリケーション(認証ポリシー)を設定する。
4. **Infisical自身の秘密情報を投入**(循環依存のため、Infisical経由では取得できない。
   このリポジトリにrsyncされている `infisical/.env` の内容を使う。**このファイルは
   `.gitignore`済みでコミットしない**):
   ```
   kubectl create namespace infisical
   kubectl -n infisical create secret generic infisical-env --from-env-file=infisical/.env
   ```
5. **Grafanaの秘密情報を投入**(`grafana/docker-compose.yml` は `.gitignore`済み、
   埋め込まれていた `GF_SECURITY_ADMIN_PASSWORD` と `GF_AUTH_GITHUB_CLIENT_SECRET` を使う):
   ```
   kubectl create namespace monitoring
   kubectl -n monitoring create secret generic grafana-secrets \
     --from-literal=admin-password='<GF_SECURITY_ADMIN_PASSWORD>' \
     --from-literal=github-client-secret='<GF_AUTH_GITHUB_CLIENT_SECRET>'
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
8. **2026kosensaiリポジトリのInfisical(production/staging両環境)に `GHCR_PULL_TOKEN`
   (read:packages スコープのPAT)を追加**(prod/test namespace用のimagePullSecret)。

これ以降、共有プラットフォーム設定は `config` への push (`main`ブランチ) で、
アプリ本体は `2026kosensai` の `prod`/`test` ブランチへのpushで、それぞれ独立に
コードから再現・更新される。

## 動作確認

```sh
kubectl kustomize k8s/overlays/shared      # レンダリング確認
kubectl apply --dry-run=server -k k8s/overlays/shared
```

適用後:
- `kubectl get svc -n kube-system traefik` で `TYPE=ClusterIP` になっていること
  (公開ポートを一切bindしていないこと)。
- `curl -I https://grafana.nara-kosensai.com/`, `https://infisical.nara-kosensai.com/`,
  `https://storybook.nara-kosensai.com/` が200/302で応答すること。
- GrafanaでLoki/Prometheusのデータソードが有効で、各namespaceのPodログ・
  node-exporter/Traefikメトリクスが見えること。
