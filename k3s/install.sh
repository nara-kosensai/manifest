#!/usr/bin/env bash
# k3s シングルノードクラスタのブートストラップスクリプト。
# VPS上でroot(またはsudo)で一度だけ実行する。再実行しても安全(k3sのインストーラは冪等)。
#
# --disable=servicelb : LoadBalancer型ServiceがklipperLBでホストポートを
#   バインドしないようにする。外部通信はCloudflare Tunnel経由のみのため、
#   ノードの公開インターフェースには何もbindしない設計にする。
# --write-kubeconfig-mode 644 : デプロイ用ユーザーがkubeconfigを読めるようにする
#   (rootのみ読める0600のままだと、CIからのsshユーザーでkubectlが使えない)。
set -euo pipefail

# get.k3s.io のインストーラは非rootでも内部でsudoに自動昇格するが、その昇格は
# このスクリプトの以降の処理(/var/lib/rancher/k3s/server/manifests への書き込み等)
# には引き継がれない。スクリプト全体を一貫してroot権限で実行するため、
# 非rootで呼ばれた場合はここでsudoに自己再実行する。
if [ "$(id -u)" -ne 0 ]; then
  exec sudo --preserve-env=TLS_SAN "$0" "$@"
fi

TLS_SAN="${TLS_SAN:-}"

INSTALL_ARGS=(
  "--write-kubeconfig-mode" "644"
  "--disable=servicelb"
)

if [ -n "${TLS_SAN}" ]; then
  INSTALL_ARGS+=("--tls-san" "${TLS_SAN}")
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${INSTALL_ARGS[*]}" sh -

echo "k3s installed. Waiting for node to become Ready..."
until kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready'; do
  sleep 2
done

echo "Applying Traefik HelmChartConfig (ClusterIP only, no public port binding)..."
install -d -m 0755 /var/lib/rancher/k3s/server/manifests
install -m 0644 "$(dirname "$0")/traefik-config.yaml" /var/lib/rancher/k3s/server/manifests/traefik-config.yaml

echo "Waiting for Traefik to pick up the new config..."
kubectl -n kube-system rollout status deployment/traefik --timeout=180s

echo "Applying Grafana Alloy logging DaemonSet (ships pod logs to the host's Loki)..."
install -m 0644 "$(dirname "$0")/alloy-logging.yaml" /var/lib/rancher/k3s/server/manifests/alloy-logging.yaml

echo "Applying local-path-retain StorageClass (for data that must survive PVC/namespace deletion)..."
install -m 0644 "$(dirname "$0")/local-path-retain-storageclass.yaml" /var/lib/rancher/k3s/server/manifests/local-path-retain-storageclass.yaml

echo "Done. Verify with: kubectl get svc -n kube-system traefik"
echo "It must show TYPE=ClusterIP (not LoadBalancer) with no host port bound."
