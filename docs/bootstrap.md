# 初期セットアップ手順

新しいVPSにこの構成をゼロから構築する場合の手順。コードで完全に再現できない箇所
(秘密情報の性質、または初回のみのCLI操作)をまとめたもので、通常の運用では参照しない。
全体のアーキテクチャは[architecture.md](architecture.md)、日々のトラブルシュートは
[operations.md](operations.md)を参照。

1. **VPSにk3sをインストール**: `k3s/install.sh` をVPS上で実行する(root権限が
   必要だが、非rootで呼んでもスクリプト自身が自動的に`sudo`へ昇格する)。
   ```
   ./k3s/install.sh
   ```
   k3s本体のインストールに加えて、`traefik-config.yaml` / `alloy-logging.yaml` /
   `local-path-retain-storageclass.yaml` を `/var/lib/rancher/k3s/server/manifests/`
   に配置するところまでこのスクリプトが自動で行う(追加のコマンドは不要)。
   以後これらのファイルを更新した場合は、`manifest`リポジトリへのpushでCIが
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
7. **`manifest`リポジトリのGitHub Actions環境(`production-vps`)にSSH関連シークレットを設定**:
   `SSH_PRIVATE_KEY` / `SSH_USER` / `SSH_HOST` / `CLOUDFLARED_CLIENT_ID` /
   `CLOUDFLARED_CLIENT_SECRET`(値は2026kosensaiリポジトリのものと同じでよい、
   SSH管理用Cloudflare Accessトンネル経由でVPSに入るため)。**`SSH_USER`はVPS上のCI専用
   アカウント(例: `github`)を指し、対話ログインで使う`admin`アカウントとは別物**。この
   `SSH_USER`のホームディレクトリ(`/home/<SSH_USER>`)には自由に書き込めること、また
   `/var/lib/rancher/k3s/server/manifests/` へのパスワードなし`sudo`を実行できることが必要。
8. **2026kosensaiリポジトリの`production-vps`/`test-vps` environmentに
   `GHCR_PULL_TOKEN`(read:packages スコープのPAT)をGitHub Environment Secretとして
   追加**(prod/test namespace用のimagePullSecret。Infisicalは経由しない)。
9. **ArgoCD自体をインストール**: 手順1〜8を終えた状態で`manifest`リポジトリの`main`への
   pushでCIが`argocd`を適用し、ArgoCD本体が立ち上がる
   (`kubectl -n argocd get pods`で確認)。
10. **`manifest`リポジトリへの読み取り用SSH Deploy Keyを発行**: すべてのk8sマニフェスト
    (共有プラットフォーム設定・アプリ本体・website)がこの1リポジトリに集約されたため、
    ArgoCDが直接gitをpullする対象は`manifest`リポジトリのみでよい。`Settings > Deploy keys`
    で読み取り専用(Write access不要)のDeploy Keyを追加し、対応する秘密鍵をArgoCDに登録する:
    ```
    kubectl -n argocd create secret generic manifest-repo \
      --from-literal=type=git \
      --from-literal=url=git@github.com:nara-kosensai/manifest.git \
      --from-file=sshPrivateKey=<manifest用秘密鍵のパス>
    kubectl -n argocd label secret manifest-repo argocd.argoproj.io/secret-type=repository
    ```
    (`2026kosensai`リポジトリはビルド/イメージpushとタグ更新commitのみを行い、ArgoCDが
    直接読み取ることはないため、こちらへのDeploy Keyは不要。ただし`2026kosensai`側のCIが
    `manifest`リポジトリへコミット&プッシュできるよう、`manifest`への書き込み権限を持つ
    別のDeploy Key/PATを`2026kosensai`側のGitHub Environment Secretとして用意すること)。
11. **ArgoCDのApp-of-appsをブートストラップ**: `root-app.yaml`だけを一度きり手動でapplyする
    (以降はこのファイル自体もgit経由でArgoCDが管理する)。
    ```
    kubectl apply -f applications/root-app.yaml
    ```
    続けて`network`/`monitoring`/`pgadmin`/`web-static`/`app-prod`/`app-test`/
    `website-prod`/`website-test`をはじめ各Applicationが`argocd`namespaceに現れる
    (`kubectl -n argocd get applications`)。**本番影響を避けるため、`kubectl apply`直後は
    各Applicationで`argocd app diff <name>`を実行し、gitとVPS上の実際の状態に差分がないことを
    確認してから運用を続けること**(差分がある場合、意図しないリソースの再作成/削除が
    起きうる)。
12. **ArgoCD UI用のCloudflare Accessポリシー**: `argocd.nara-kosensai.com`に対して
    Cloudflareダッシュボード側でAccessアプリケーション(認証ポリシー、pgAdminと同様の設定)を
    追加する。ArgoCDの初期adminパスワードは`kubectl -n argocd get secret
    argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`で取得できる
    (初回ログイン後、ローテーション/削除を推奨)。
13. **Teams通知用webhook URLを投入**(`argocd/argocd-notifications-cm-patch.yaml`
    が参照する`$teams-webhook-url`の実体。Power Automateフローの署名付きURLで機微情報のため
    git管理しない):
    ```
    kubectl -n argocd create secret generic argocd-notifications-secret \
      --from-literal=teams-webhook-url='<Power AutomateフローのHTTPトリガーURL>'
    ```
    (Secretを更新した場合は`kubectl -n argocd rollout restart
    deployment/argocd-notifications-controller`で反映する)。
14. **本番アプリ用Origin Authentication(mTLS)のCloudflare側設定**(仕組み自体は
    [architecture.md#tls--mtls](architecture.md#tls--mtls)を参照。`nara-kosensai.com` /
    `www.nara-kosensai.com`のみが対象):
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
       silent DROPする。`install.sh`が初回導入・有効化し、以後は`deploy.yml`が
       更新の都度再適用、systemd timerがIPレンジを日次で自動更新する
       (**このスクリプトはnftablesを前提とする**)。
    5. 動作確認後、`nara-kosensai.com` / `www.nara-kosensai.com` のDNSレコードを
       Tunnel向けCNAME(`<tunnel-id>.cfargotunnel.com`)から、VPSの公開IPを指す
       A(/AAAA)レコード(Proxied継続)に切り替える。
    6. 切り替え後、`network/cloudflared-configmap.yaml` の`ingress`から
       `nara-kosensai.com` / `www.nara-kosensai.com` のエントリを削除してよい
       (test/admin系は残す)。

これ以降、共有プラットフォーム設定・アプリ本体・websiteのマニフェストはすべて`manifest`
への push(`main`ブランチ)でコードから再現・更新される。`2026kosensai`リポジトリの
CIはイメージのbuild/pushと、`manifest`側マニフェストのイメージタグ更新commit&pushだけを
行う。ただし実際のマニフェストapplyはArgoCDが担うため、CIのpush自体はgitの内容を
更新するだけであり、反映確認はArgoCD UI/CLIで行う。

## 構築後の動作確認

```sh
for dir in network monitoring pgadmin web-static app-prod app-test website-prod website-test; do
  kubectl kustomize "$dir"                       # レンダリング確認
  kubectl apply --dry-run=server -k "$dir"
done
kubectl kustomize argocd     # ArgoCD自体のレンダリング確認
```

適用後:

- `kubectl get svc -n kube-system traefik` で `TYPE=ClusterIP` になっていること
  (公開ポートを一切bindしていないこと)。
- `curl -I https://grafana.nara-kosensai.com/`, `https://storybook.nara-kosensai.com/`,
  `https://argocd.nara-kosensai.com/`(Cloudflare Access認証後)が200/302で応答すること。
- `kubectl -n argocd get applications` で全Applicationが`Sync Status: Synced`,
  `Health: Healthy`になっていること。
- GrafanaでLoki/Prometheusのデータソースが有効で、各namespaceのPodログ・
  node-exporter/Traefikメトリクスが見えること。
- `nft list table ip cloudflare_mtls` / `nft list table ip6 cloudflare_mtls6`
  でCloudflareのIPレンジが入ったsetが存在すること。VPS外の任意のIPから
  `curl -v https://<VPSの公開IP>:443 -H "Host: nara-kosensai.com"` を実行し、
  TCP接続自体がタイムアウトする(応答が一切返らない)ことを確認する。

## hr(シフト調整システム)の初回Secret投入

`hr/`のマニフェストはArgoCD Application `hr`が自動syncするが、以下はgit管理外のため
一度きり手動で投入する(`hr` namespaceはArgoCDが作成するので、先に一度syncさせるか
`kubectl create namespace hr`しておく)。

```bash
# アプリ+DB共通の環境変数。DATABASE_URLとPOSTGRES_*は値を揃えること
kubectl -n hr create secret generic hr-env \
  --from-literal=POSTGRES_USER=hr \
  --from-literal=POSTGRES_PASSWORD='<強いパスワード>' \
  --from-literal=POSTGRES_DB=hr \
  --from-literal=DATABASE_URL='postgres://hr:<同じパスワード>@db:5432/hr' \
  --from-literal=AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=AUTH_URL=https://hr.nara-kosensai.com \
  --from-literal=AUTH_MICROSOFT_ENTRA_ID_ID=... \
  --from-literal=AUTH_MICROSOFT_ENTRA_ID_SECRET=... \
  --from-literal=ALLOWED_TENANT_IDS=... \
  --from-literal=SMTP_URL=smtp://...
# NODE_ENV=production のままにし、AUTH_DEV_LOGIN は絶対に設定しない

# GHCR pull(イメージがprivateの場合。web-staticと同じ手順/トークンで可)
kubectl -n hr create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT(read:packages)>
```

あわせてCloudflare側で`hr.nara-kosensai.com`のTunnel public hostname(DNS route)を追加する
(`network/cloudflared-configmap.yaml`にはingressエントリ追加済み)。
