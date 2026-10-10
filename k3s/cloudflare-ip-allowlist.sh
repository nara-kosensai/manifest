#!/usr/bin/env bash
# 443/tcp (Origin Authentication, websecure-mtls エントリーポイント) 宛の
# パケットを、Cloudflareが公開しているIPレンジからのものだけに絞り、それ以外は
# nftablesのraw prerouting(conntrack/DNATより前段)でsilent DROPする。
#
# TraefikのmTLS検証(TLSOption, clientAuthType: RequireAndVerifyClientCert)は
# クライアント証明書を検証するが、それ自体はTCPハンドシェイクが成立し
# TLSの致命的アラートを返す=「応答」になってしまう。ここでのIPレベルの
# サイレントDROPが本体で、mTLS検証はその内側の保険という位置付け。
# raw prerouting段階で弾くため、hostPort用のDNAT(kube-proxy/CNIが設定する
# natテーブル、priority dstnat)より先に処理され、Cloudflare以外からのパケットは
# Traefik/Podに一切到達しない。
#
# 【重要】必ず外部公開インターフェース(`iifname`)に絞ること。
# 過去に`tcp dport 443`だけで(インターフェース指定なしで)判定していたところ、
# クラスタ内部のPod発トラフィック(kubernetes ServiceのClusterIP `10.43.0.1:443`
# 宛のAPIサーバーアクセス等、送信元がPod CIDRで当然Cloudflare IPではない)まで
# 巻き込んでdropしてしまい、kube-apiserverへの内部到達性を破壊してSelmController
# のTraefikデプロイをクラッシュループさせ、本番障害を起こした。dport 443を使う
# 内部ClusterIP(kubernetes.default含む)は複数存在するため、宛先IPで区別するより
# 「外部NICから届いたパケットか」で区別する方が安全(内部トラフィックは
# 定義上このインターフェースを通らない)。
#
# 既存のk3s/kube-proxy/CNIが使うnftables/iptablesルールには一切触れない。
# 専用テーブル(ip cloudflare_mtls / ip6 cloudflare_mtls6)だけを毎回flush&
# 再構築するため冪等。443番以外の通信・他ホストへの通信には影響しない
# (80番はそもそもClusterIPのみでホストにbindされていないため対象外)。
#
# SSH管理アクセスは別のCloudflare Access Tunnel(VPS側からのoutbound接続)を
# 使っており、本スクリプトのinboundフィルタリングとは無関係。誤って
# ロックアウトすることはない。
#
# CloudflareのIPレンジは変動するため、cloudflare-ip-allowlist.timer
# (systemd, 日次)がこのスクリプトを再実行して差分を反映する。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

command -v nft >/dev/null || { echo "::error::nft (nftables) not found. This script assumes nftables, not iptables-legacy/ufw." >&2; exit 1; }

# デフォルトルートに使われている外部公開インターフェースを動的に特定する
# (VPS再構築等でインターフェース名が変わっても追従できるよう、ハードコードしない)。
EXT_IFACE=$(ip -4 route show default | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -1)
if [ -z "${EXT_IFACE}" ]; then
  echo "::error::Could not determine the external interface from the default route" >&2
  exit 1
fi

ipv4_ranges=$(curl -sf https://www.cloudflare.com/ips-v4)
ipv6_ranges=$(curl -sf https://www.cloudflare.com/ips-v6)

if [ -z "${ipv4_ranges}" ] || [ -z "${ipv6_ranges}" ]; then
  echo "::error::Failed to fetch Cloudflare IP ranges from cloudflare.com" >&2
  exit 1
fi

RULESET_FILE=/etc/nftables.d/cloudflare-mtls.conf
install -d -m 0755 /etc/nftables.d

{
  echo "table ip cloudflare_mtls {"
  echo "  set cf_ipv4 {"
  echo "    type ipv4_addr; flags interval"
  echo "    elements = { $(echo "${ipv4_ranges}" | paste -sd, -) }"
  echo "  }"
  echo "  chain prerouting {"
  echo "    type filter hook prerouting priority raw; policy accept;"
  echo "    iifname \"${EXT_IFACE}\" tcp dport 443 ip saddr != @cf_ipv4 drop"
  echo "  }"
  echo "}"
  echo "table ip6 cloudflare_mtls6 {"
  echo "  set cf_ipv6 {"
  echo "    type ipv6_addr; flags interval"
  echo "    elements = { $(echo "${ipv6_ranges}" | paste -sd, -) }"
  echo "  }"
  echo "  chain prerouting {"
  echo "    type filter hook prerouting priority raw; policy accept;"
  echo "    iifname \"${EXT_IFACE}\" tcp dport 443 ip6 saddr != @cf_ipv6 drop"
  echo "  }"
  echo "}"
} > "${RULESET_FILE}.tmp"

# 専用テーブルだけを削除してから再適用する(他のnftables設定には触れない)。
# `nft -f` は指定ファイル全体をアトミックに適用するため、旧ルールが消えて
# 新ルールが入るまでの間に無防備な瞬間ができることはない。
nft delete table ip cloudflare_mtls 2>/dev/null || true
nft delete table ip6 cloudflare_mtls6 2>/dev/null || true
nft -f "${RULESET_FILE}.tmp"
mv "${RULESET_FILE}.tmp" "${RULESET_FILE}"

# 起動時にも読み込まれるよう /etc/nftables.conf からincludeする(未追加なら追加)。
MAIN_CONF=/etc/nftables.conf
if [ -f "${MAIN_CONF}" ] && ! grep -qF "${RULESET_FILE}" "${MAIN_CONF}"; then
  echo "include \"${RULESET_FILE}\"" >> "${MAIN_CONF}"
fi

echo "Cloudflare IP allowlist applied for 443/tcp ($(date -u +%FT%TZ))"
