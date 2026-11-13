# k3s-gitops

GitOps repository for a personal K3s cluster, managed by ArgoCD (App of Apps).

## 叢集沿革
| 時期 | 平台 | 架構 |
| --- | --- | --- |
| 早期 | Hetzner | arm64 |
| 中期 | Hetzner | x86 |
| 現在 | Oracle Cloud (Always Free A1) | arm64 |

目前：1 台 control-plane + 1 台 worker，各 2 vCPU / 12 GB（Ubuntu, arm64）。
所有映像檔都需要有 arm64 版本。

## 架構
```
Internet ──> Cloudflare ──(Tunnel)──> cloudflared ──> Traefik (ClusterIP) ──> drawcardapp
                                                       節點不對外開放 80/443
Tailscale ──> Grafana / ArgoCD   (只經 tailnet 存取，不經公網)
```
- 公網只暴露 `drawcardapp.changken.net`，由 Cloudflare Tunnel 連入；hostname 在 Cloudflare Zero Trust 後台設定，tunnel 只設這一筆。
- TLS 由 Cloudflare 終結，叢集內走 HTTP，因此不使用 cert-manager。
- Grafana、ArgoCD 透過 Tailscale operator 暴露（`changken-k3s-grafana`、`changken-k3s-argocd`）。

## 目錄
- `root-app.yaml` - App of Apps 進入點（只掃 `apps/*.yaml`，不遞迴）
- `apps/` - ArgoCD Application（helm chart 與 `drawcardapp`）
- `apps/drawcardapp/` - drawcardapp 的 manifest（CI 會更新 `Deployment.yaml` 的映像 tag，路徑請勿移動）
- `infra/` - 純 manifest，由 `infra` app 遞迴同步：traefik 設定、cloudflared、SealedSecrets、ArgoCD 的 Tailscale Service
- `scripts/seal-secrets.sh` - 以叢集公鑰加密 credential 產出 SealedSecret

## 從零還原節點
前置：新節點上的 k3s 已安裝、本機 `kubectl` 可連線。

1. **還原 sealing key**（必須在 sealed-secrets controller 啟動前）
   ```bash
   kubectl apply -f <你保管的 sealed-secrets key 備份>.yaml   # 先移除 uid/resourceVersion/creationTimestamp
   ```
   key 備份含私鑰，**不要放進 repo**。若 key 遺失，所有 SealedSecret 都要用新 key 重新加密（見步驟 4）。
2. **安裝 ArgoCD**
   ```bash
   kubectl create ns argocd
   kubectl apply -n argocd --server-side --force-conflicts \
     -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
3. **套用 root-app**
   ```bash
   kubectl apply -f root-app.yaml
   ```
   repo 為 public，ArgoCD 不需要 repo credential。
4. **（key 遺失時）重新加密 credential**，commit 並 push
   ```bash
   bash scripts/seal-secrets.sh            # grafana + tailscale + cloudflared
   bash scripts/seal-secrets.sh cloudflared # 只加密單項
   ```
   需要：Grafana admin 帳密、Tailscale OAuth client（Devices Core + Auth Keys write，tag `tag:k8s-operator`）、Cloudflare Tunnel token。
5. **設定 Cloudflare Tunnel**：待 cloudflared 連線後，在 Zero Trust 後台新增 public hostname
   `drawcardapp.changken.net` → `http://traefik.kube-system.svc.cluster.local:80`。
6. **設定 ArgoCD admin 密碼**：讀取 `argocd-initial-admin-secret`、登入後改密碼，再刪除該 secret。
   Windows 若 `port-forward 8080` 被擋，改用其他埠（如 8443）。
   Tailscale 連線請用 `https://changken-k3s-argocd`（自簽憑證，需接受警告；argocd CLI 加 `--grpc-web`）。
   用 http 會被導向 443，所以 `infra/argocd/tailscale-svc.yaml` 同時暴露了 80 與 443。

## 注意事項
- sealed-secrets chart repo 為 `https://bitnami.github.io/sealed-secrets`（舊的 `bitnami-labs.github.io` 已 404）。
- k3s 內建 Traefik 由 `infra/traefik/helmchartconfig.yaml` 設定；此版 chart 的 Service 型別要寫在 `service.spec.type`。
- Tailscale operator 使用預設的 `operator-oauth` Secret，chart 不支援 `secretKeyRef`。
