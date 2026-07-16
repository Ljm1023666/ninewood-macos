# Cloud Migrate / SSH

## 新 Cursor 会话

请先读桌面配置（恢复服务器操作上下文）：

```
~/Desktop/九木-新会话配置.md
```

或仓库内（已 gitignore 的凭据说明）：

```
scripts/cloud-migrate/secrets/云服务器权限与凭据.md
```

## SSH（现行生产）

```bash
export KEY="$HOME/Desktop/ninewood-macos/scripts/cloud-migrate/id_ed25519_ninewood"
ssh -i "$KEY" root@8.217.208.203
```

| 项 | 值 |
|----|-----|
| 生产公网 | `8.217.208.203` |
| 域名 | `tothetomorrow.com` |
| Tailscale | `ninewood-prod` |
| 项目 | `/opt/ninewood` |

**已废弃：** `8.218.95.92`（勿再改九木 API / AI 配置）。该机若仍开机，可能只残留 `xian` / `bot` 等子域服务。

## 文件说明

| 文件 | 可提交 Git？ |
|------|----------------|
| `id_ed25519_ninewood.pub` | ✅ 公钥可以 |
| `id_ed25519_ninewood` | ❌ 私钥，已 gitignore |
| `secrets/` | ❌ 已 gitignore |
| `artifacts/` | ❌ 已 gitignore |
| `local.*` | ❌ 已 gitignore |

```bash
chmod 600 scripts/cloud-migrate/id_ed25519_ninewood
git check-ignore -v scripts/cloud-migrate/id_ed25519_ninewood
```
