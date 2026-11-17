# k3s-gitops

## `main` 有多個寫入者

除了人工 commit，其他 repo 的 CI 也會直接 push 到這個 repo 的 `main`，而這些 workflow 不在這個 repo 裡：

| 寫入者 | 只會改的地方 |
|---|---|
| DrawCardApp repo 的 `build.yaml` | `apps/drawcardapp/Deployment.yaml` 的 `image:` 行 |
| MeetingRoomSchedule repo 的 `ci.yml` | `apps/meetingroomschedule/Deployment.yaml` 的 `image:` 行 |

所以本地的 `origin/main` 隨時可能落後：

- **push 前先 `git fetch`。** push 被拒時跑 `git pull --rebase`（把本地還沒 push 的 commit 重放到 remote 最新 commit 之上），再 push 一次。
- **`main` 的歷史只往前加。** bot 的 commit 就是目前的部署版本，被蓋掉的話 Argo CD 會把 image 退回舊版；真的必須改寫歷史時用 `--force-with-lease`，並先跟使用者確認。
- **`image:` 行的 tag 由 CI 擁有。** 要上新版就到 app repo push 或重跑 workflow；要回滾就 `git revert` 對應的 bot commit。
- **新增由 CI 部署的 app** 時，回寫 step 沿用上面兩個 workflow 的重試迴圈：fetch → `reset --hard origin/main` → 改 tag → push，失敗就重來。
