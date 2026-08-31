# 運用マニュアル

発生が懸念される、または実際に発生したトラブルと、その症状・原因・診断手順・対処法をまとめる。
恒久的な設計変更を行った場合は[architecture.md](architecture.md) / `architecture.typ`側の
「障害と設計判断」節にも追記すること(このマニュアルは日々のトラブルシュート向け、
architecture側は設計判断の記録)。

VPSへの接続方法・namespace構成・シークレット管理方針の前提は[architecture.md](architecture.md)
を参照。以下では`KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl ...`を単に`kubectl ...`と略す。

## 目次

1. [Cloudflare IPアローリストの更新不具合](#1-cloudflare-ipアローリストの更新不具合)
2. [VPS再起動でホスト名が変わりk3sノードが二重化する](#2-vps再起動でホスト名が変わりk3sノードが二重化する)
3. [GHCR pullトークンの期限切れ・権限エラー(403)](#3-ghcr-pullトークンの期限切れ権限エラー403)
4. [rolloutタイムアウトの一般的な切り分け手順](#4-rolloutタイムアウトの一般的な切り分け手順)

## 1. Cloudflare IPアローリストの更新不具合

### 何が起きるか

本番オリジン(`websecure-mtls`, 443/tcp)への到達は、Cloudflareが公開するIPレンジを
`k3s/cloudflare-ip-allowlist.sh`がnftablesの`ip cloudflare_mtls` / `ip6 cloudflare_mtls6`
テーブルに反映することで制限している(詳細は[architecture.md#公開ポート](architecture.md#公開ポート))。
このスクリプトは次の2経路で実行される。

- VPS上の`cloudflare-ip-allowlist.timer`(systemd、日次 + `RandomizedDelaySec=1h`)
- `manifest`リポジトリの`main`へのpush時にCIが都度再実行(`.github/workflows/deploy.yml`)

この更新が滞ると、Cloudflareが新しく追加/変更したIPレンジからのリクエストが
`iifname == ens3 かつ saddr ∉ Cloudflare IP` のdrop条件に引っかかり、**正規のCloudflare
Edgeからのリクエストがサイレントに落とされる**。ユーザー側の症状はCloudflareの
**522 (Connection timed out)** や **524 (A timeout occurred)** で、Traefik/アプリのログには
何も残らない(パケットがraw preroutingで落ちるため、TCPハンドシェイクにすら到達しない)。
断続的・一部ユーザーだけで再現するため気づきにくい。

より深刻なのは、スクリプトが**部分的に失敗した場合**の挙動である。処理順序は

1. `curl`でIPv4/IPv6レンジを取得
2. 新しいruleset(`.tmp`ファイル)を組み立てる
3. 既存の`cloudflare_mtls` / `cloudflare_mtls6`テーブルを`nft delete table`で削除
4. `nft -f`で新rulesetを適用

`curl`が失敗した場合は1の時点(まだ何もnftablesに触れていない)で`set -euo pipefail`により
異常終了するため、**古いルールが残ったまま**でフェイルセーフに倒れる(=古いIPレンジで
引き続き制限がかかる。新しいCloudflare IPからは522になりうるが、無防備にはならない)。

一方、3の削除には成功したが4の`nft -f`が何らかの理由(rulesetの構文異常、`nft`コマンド自体の
一時的な問題等)で失敗した場合、**dropルールが一切存在しない空白の状態**が生まれる。この間は
443/tcpへの到達がCloudflare IP以外からも通ってしまう(mTLS検証はTraefik側でなお必要だが、
IPレベルの一次防御がスクリプト完走まで失われる)。次回のtimer実行(最大24時間+ランダム遅延後)
まで気づかない可能性がある。

### 診断

```bash
# timer/serviceの状態と直近の実行結果
systemctl status cloudflare-ip-allowlist.timer
systemctl status cloudflare-ip-allowlist.service
journalctl -u cloudflare-ip-allowlist.service --since "-7d"

# 現在nftablesに読み込まれているCloudflare IPレンジの件数・中身
sudo nft list set ip cloudflare_mtls cf_ipv4 | head -5
sudo nft list set ip6 cloudflare_mtls6 cf_ipv6 | head -5

# 最新のCloudflare公式レンジと比較(手元で取得して見比べる)
curl -s https://www.cloudflare.com/ips-v4
curl -s https://www.cloudflare.com/ips-v6

# dropルール自体が存在するか(空白状態になっていないかの確認)
sudo nft list table ip cloudflare_mtls
sudo nft list table ip6 cloudflare_mtls6
```

`nft list table`が空、あるいはテーブル自体が存在しない場合は防御が失われている状態なので
最優先で次の手動再実行を行う。

### 対処

```bash
# 手動で即座に再実行(冪等なので何度実行しても安全)
sudo /usr/local/sbin/cloudflare-ip-allowlist.sh

# timerが無効化されている/失敗し続けている場合
sudo systemctl enable --now cloudflare-ip-allowlist.timer
sudo systemctl reset-failed cloudflare-ip-allowlist.service
```

再実行後は上記「診断」のコマンドで`nft list table`にルールが復元されていることを必ず確認する。

### 恒久対策として検討の余地がある事項(未実装、既知の課題)

- 現状はスクリプト失敗時のアラート通知が無い。`ExecStart`失敗時にPrometheus
  Alertmanager等へ通知する仕組みがあると早期検知できる(現状はGrafana/Prometheusは
  稼働しているが、systemdユニットの失敗を監視する設定は入っていない)。
- 3→4の間で失敗した場合に空白状態になる問題は、`nft -f`を新テーブル名(例:
  `cloudflare_mtls_new`)に対して行ってから`rename`する、あるいは既存テーブルを保持したまま
  差分更新する方式に変えることで解消できる可能性がある。

## 2. VPS再起動でホスト名が変わりk3sノードが二重化する

### 何が起きるか

2026-08-28にVPSプロバイダ側のメンテナンスと思われるOS更新(カーネル`6.1.0-49-cloud-amd64`→
`6.12.105+deb13-cloud-amd64`)を伴う再起動が発生し、その際にOSの静的ホスト名が
`x162-43-87-201`から`kosensai`に変化した。k3sはノード名にOSホスト名をそのまま使う設定
だったため、k3sは同じ物理マシンを**別のノード**として新規登録し、旧ノードオブジェクト
(`x162-43-87-201`)は`kubelet stopped posting node status`のまま`NotReady`で残った。

このクラスタは`local-path`(ノードローカルストレージ)を使っており、既存のPersistentVolumeは
すべて`nodeAffinity`で旧ノード名(`x162-43-87-201`)を固定的に参照していた。新ノード名
(`kosensai`)はこのaffinityにマッチしないため、PVCを使う全Pod(`db`, `redis`, `loki`,
`grafana`, `prometheus`等のStatefulSet/Deployment)が新ノードにスケジュールできず
`Pending`のまま止まった。CI(`deploy.yml`)の`rollout status`待ちがタイムアウトするのは
この症状の一つの現れ方。

### 診断

```bash
kubectl get nodes -o wide
# 2つ以上のノードが同じ INTERNAL-IP を持っていないか確認

kubectl get pods -A -o wide
# STATUS が Pending のものが PVC を使っているか確認
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}'

kubectl describe node <NotReadyのノード名>
# Ready condition の reason が "NodeStatusUnknown" (kubelet stopped posting node status) なら
# そのノードの実体は既に無い(=OS側でホスト名/インスタンスが変わった)

kubectl describe pod <pending pod> -n <ns>
# Events に "node(s) didn't match PersistentVolume's node affinity" が出ていれば本事象そのもの

kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}'
# 各PVが指しているノード名を一覧できる。現在のノード名と食い違っていないか確認

hostnamectl
# 現在のOSホスト名を確認。k3sのノード名と食い違っていれば根本原因が再現している
```

### 対処(実施済みの恒久対策)

PersistentVolumeの`nodeAffinity`は作成後に変更不可(immutable)なため、9個のPVすべてを
削除→再作成するのは本番データ(`db-data`等、`reclaimPolicy: Retain`のもの含む)を巻き込む
リスクが高い。代わりに**k3s側のノード名をOSホスト名から独立させ、固定した**。

```bash
# /etc/systemd/system/k3s.service の ExecStart に以下を追加済み
#   '--node-name' \
#   'x162-43-87-201' \

sudo systemctl daemon-reload
sudo systemctl restart k3s
```

これにより、OSホスト名が今後再び変わっても(`kosensai`のまま/別の名前に変わっても)、
k3sは常に`x162-43-87-201`としてノード登録される。PVの`nodeAffinity`もこの名前を参照して
いるため、以後は再発しない。

もしノード名を新しいホスト名(`kosensai`)側に正式移行したくなった場合は、上記
`--node-name`設定を外すのではなく、**PVの`reclaimPolicy`を一時的に`Retain`へ揃えた上で、
PVオブジェクトを1つずつ削除→同じ`hostPath`/`claimRef`で`nodeAffinity`だけ書き換えて
再作成し、対応するPVCと再バインドさせる**必要がある。実データは直接は消えないが、
`local-path-provisioner`のDelete処理が絡む操作なので必ず事前にVPS上の実ディレクトリ
(`/opt/local-path-provisioner/`配下、またはlocal-pathのConfigMapで指定されたパス)を
バックアップしてから行うこと。

### もし再発したら(応急処置)

```bash
# 既に別名で再登録されてしまった場合、実体のない古いノードを削除して
# Pod のスケジューリングを即座に再試行させる
kubectl delete node <NotReadyな旧ノード名>
kubectl get pods -A -o wide   # 数十秒待って Pending が解消するか確認
```

ただしこれは対症療法。`--node-name`固定が外れていないか(`cat /etc/systemd/system/k3s.service`)
を必ず合わせて確認すること。

## 3. GHCR pullトークンの期限切れ・権限エラー(403)

### 何が起きるか

`prod` / `test` namespaceの`backend`(2026kosensaiリポジトリ管理)や、`web-static`
namespaceの各Deployment(README.md参照)は、`ghcr-pull`という`kubernetes.io/dockerconfigjson`
Secretを使ってGHCRの非公開イメージをpullする。このSecretはCIでは投入されず、
[README.md](../README.md)の手順に従い`read:packages`スコープのPersonal Access Token(PAT)
で手動作成したもの(ブートストラップ時の一度きりの手動投入)。

PATには有効期限を設定できるため、期限切れになるとイメージpullが

```
Failed to pull and unpack image ...: failed to resolve reference ...: failed to authorize:
failed to fetch oauth token: ... 403 Forbidden
```

で失敗し、Podは`ImagePullBackOff`のまま起動しない。新しいイメージのrolloutが来ても
既存Podは動き続けるため気づきにくいが、Pod再作成(ノード移動、`rollout restart`、
再起動等)のタイミングで突然表面化する。

### 診断

```bash
kubectl get pods -n prod -n test -n web-static -o wide | grep -E 'ImagePull|ErrImagePull'
kubectl describe pod -n <ns> <pod> | tail -20   # 403 Forbidden の詳細を確認
kubectl get secret ghcr-pull -n <ns> -o jsonpath='{.metadata.creationTimestamp}'
```

### 対処

1. GitHubで`read:packages`スコープを持つ新しいPAT(Fine-grained PATでも可、対象パッケージへの
   読み取り権限が必要)を発行する。
2. 各namespaceで`ghcr-pull` Secretを作り直す。

   ```bash
   kubectl -n <ns> delete secret ghcr-pull
   kubectl -n <ns> create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io --docker-username=<github-username> \
     --docker-password=<新しいPAT>
   ```

3. 既に`ImagePullBackOff`になっているPodを再作成して即座に反映させる。

   ```bash
   kubectl delete pod -n <ns> <pod>   # Deployment/StatefulSet配下なら自動で再作成される
   ```

対象namespace(`prod` / `test` / `web-static`)すべてで同じ手順が必要な点に注意。

## 4. rolloutタイムアウトの一般的な切り分け手順

CI(`deploy.yml`)の`kubectl rollout status ... --timeout=...`が失敗した場合の一般的な
切り分け順序。上記1〜3のいずれにも当てはまらない場合に使う。

```bash
kubectl get pods -A -o wide
# Pending / CrashLoopBackOff / ImagePullBackOff / Error のいずれかを確認

# Pending → だいたいスケジューリング不能。イベントで理由を特定
kubectl describe pod -n <ns> <pod>   # Events欄の FailedScheduling を確認

# CrashLoopBackOff → アプリ側のエラーを確認
kubectl logs -n <ns> <pod> --previous

# ノード自体の異常を疑う場合
kubectl get nodes -o wide
kubectl describe node <node>   # Conditions / Events を確認
```

`FailedScheduling`で"node(s) didn't match PersistentVolume's node affinity"が出ていれば
[§2](#2-vps再起動でホスト名が変わりk3sノードが二重化する)、"ImagePullBackOff"かつ`403`が
出ていれば[§3](#3-ghcr-pullトークンの期限切れ権限エラー403)を参照。原因不明のタイムアウトが
本番ホストでのみ発生する場合は、Cloudflare側の522/524エラーコードと合わせて
[§1](#1-cloudflare-ipアローリストの更新不具合)も疑うこと。
