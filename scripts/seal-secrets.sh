#!/usr/bin/env bash
# 以叢集目前的 sealed-secrets 公鑰加密 credential，產出 SealedSecret yaml。
# 明文只經由 read -s 輸入，不回顯、不落地、不進 shell history。
#
# 用法（在 repo 根目錄）：
#   bash scripts/seal-secrets.sh              # 全部（grafana + tailscale + cloudflared + meetingroomschedule）
#   bash scripts/seal-secrets.sh cloudflared  # 只加密 cloudflared tunnel token
#   bash scripts/seal-secrets.sh grafana|tailscale
#   bash scripts/seal-secrets.sh meetingroomschedule  # app 的連線字串與 Supabase 設定
#   bash scripts/seal-secrets.sh ghcr                 # 選用：GHCR package 為 private 時的 pull secret（不含在 all）
# kubectl 指令可用環境變數覆寫，例如 KUBECTL=kubectl bash scripts/seal-secrets.sh
set -euo pipefail

CTRL=sealed-secrets-controller
NS=kube-system
KUBECTL=${KUBECTL:-snap run kubectl}
WHAT=${1:-all}

seal() { # seal <name> <namespace> <out> key=value...
  local name=$1 ns=$2 out=$3; shift 3
  local args=()
  for kv in "$@"; do args+=("--from-literal=$kv"); done
  mkdir -p "$(dirname "$out")"
  $KUBECTL create secret generic "$name" -n "$ns" --dry-run=client -o json "${args[@]}" \
    | kubeseal --controller-name "$CTRL" --controller-namespace "$NS" --format yaml \
    > "$out"
  echo "✔ $out"
}

if [[ $WHAT == all || $WHAT == grafana ]]; then
  read -rp  "Grafana admin user [admin]: " GUSER; GUSER=${GUSER:-admin}
  read -rsp "Grafana admin password: " GPASS; echo
  seal grafana-admin-secret monitoring infra/monitoring/grafana-admin-sealed.yaml \
    "admin-user=$GUSER" "admin-password=$GPASS"
  unset GPASS GUSER
fi

if [[ $WHAT == all || $WHAT == tailscale ]]; then
  read -rp  "Tailscale OAuth client_id: " TSID
  read -rsp "Tailscale OAuth client_secret: " TSSECRET; echo
  seal operator-oauth tailscale infra/tailscale/sealed-oauth.yaml \
    "client_id=$TSID" "client_secret=$TSSECRET"
  unset TSID TSSECRET
fi

if [[ $WHAT == all || $WHAT == cloudflared ]]; then
  read -rsp "Cloudflare Tunnel token: " CFTOKEN; echo
  seal cloudflared-token cloudflared infra/cloudflared/sealed-token.yaml \
    "token=$CFTOKEN"
  unset CFTOKEN
fi

if [[ $WHAT == all || $WHAT == meetingroomschedule ]]; then
  echo "MeetingRoomSchedule：連線字串請從 Supabase 後台 Connect 複製 Session pooler（port 5432）"
  read -rsp "ConnectionStrings__Database: " MRSDB; echo
  read -rp  "Supabase__Url: " MRSURL
  read -rsp "Supabase__AnonKey: " MRSANON; echo
  read -rp  "DemoSeed__EmailDomain: " MRSDOMAIN
  seal meetingroomschedule-secrets meetingroomschedule apps/meetingroomschedule/SealedSecret.yaml \
    "ConnectionStrings__Database=$MRSDB" "Supabase__Url=$MRSURL" \
    "Supabase__AnonKey=$MRSANON" "DemoSeed__EmailDomain=$MRSDOMAIN"
  unset MRSDB MRSURL MRSANON MRSDOMAIN
fi

if [[ $WHAT == ghcr ]]; then
  read -rp  "GitHub username: " GHUSER
  read -rsp "GitHub PAT（只需 read:packages）: " GHPAT; echo
  out=apps/meetingroomschedule/GhcrPullSealedSecret.yaml
  $KUBECTL create secret docker-registry ghcr-pull -n meetingroomschedule --dry-run=client -o json \
    --docker-server=ghcr.io --docker-username="$GHUSER" --docker-password="$GHPAT" \
    | kubeseal --controller-name "$CTRL" --controller-namespace "$NS" --format yaml \
    > "$out"
  echo "✔ $out"
  unset GHUSER GHPAT
fi

echo "完成。確認 git diff 只有 encryptedData 後再 commit/push。"
