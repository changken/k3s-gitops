#!/usr/bin/env bash
# 以叢集目前的 sealed-secrets 公鑰加密 credential，產出 SealedSecret yaml。
# 明文只經由 read -s 輸入，不回顯、不落地、不進 shell history。
# 用法（在 repo 根目錄、Git Bash）： bash scripts/seal-secrets.sh
set -euo pipefail

CTRL=sealed-secrets-controller
NS=kube-system

seal() { # seal <name> <namespace> <out> key=value...
  local name=$1 ns=$2 out=$3; shift 3
  local args=()
  for kv in "$@"; do args+=("--from-literal=$kv"); done
  snap run kubectl create secret generic "$name" -n "$ns" --dry-run=client -o json "${args[@]}" \
    | kubeseal --controller-name "$CTRL" --controller-namespace "$NS" --format yaml \
    > "$out"
  echo "✔ $out"
}

read -rp  "Grafana admin user [admin]: " GUSER; GUSER=${GUSER:-admin}
read -rsp "Grafana admin password: " GPASS; echo
read -rp  "Tailscale OAuth client_id: " TSID
read -rsp "Tailscale OAuth client_secret: " TSSECRET; echo

mkdir -p infra/monitoring infra/tailscale
seal grafana-admin-secret monitoring infra/monitoring/grafana-admin-sealed.yaml \
  "admin-user=$GUSER" "admin-password=$GPASS"
seal operator-oauth tailscale infra/tailscale/sealed-oauth.yaml \
  "client_id=$TSID" "client_secret=$TSSECRET"

unset GPASS TSSECRET TSID GUSER
echo "完成。確認 git diff 只有 encryptedData 後再 commit/push。"
