# 生产数据类型清单

> **基准：** 2026-07-19 · `8.217.208.203`  
> **补数：** `community-seed-v1` 已全量跑完  
> **真实化：** `polish-community-realism-v1` 已清除 `用户_*` / `发卡_*` 昵称、空头像、消息中的 `[community-seed-v1]` 前缀（2026-07-19）

## 1. 账号覆盖率（891 用户）— 补数后

| 数据类型 | 有数据用户数 | 覆盖率 |
|----------|-------------|--------|
| seed 钱包流水 (`referenceType=community-seed-v1`) | **891** | **100%** |
| Follow | **891** | **100%** |
| CircleMember | **891** | **100%** |
| Message | **891** | **100%** |
| DemandFavorite | **891** | **100%** |
| LoopRun（`initiatorRef=user:<id>`） | **891** | **100%** |
| ServiceCard | **272** | **31%**（设计目标约 30%） |
| Order（任一侧） | **143** | **16%**（轻量订单样本） |

---

## 2. 关键表行数（补数后快照）

| 域 | 表 | 行数 |
|----|----|-----|
| 账号 | User | 891 |
| | UserTag | ~4072 |
| | CertifiedProvider | 61 |
| **社交** | Follow | **1871** |
| | Circle | **28**（含 8 个 `community-seed-v1·回社区-*`） |
| | CircleMember | **1030** |
| **消息** | Message | **1893** |
| **收藏** | DemandFavorite | **969** |
| **服务卡** | ServiceCard | **272** |
| | ServiceCardClaim | **266** |
| | CardAttachment | 2 |
| **钱包** | WalletLedger | **920** |
| **回** | LoopRun | **27577**（+约 2k seed） |
| | LoopEvent | **55189** |
| **交易** | Order | **133** |
| **福利** | WelfareReward | **35** |

---

## 3. 脚本与标记

- 脚本：[`scripts/cloud-migrate/seed-community-loop-v1.mjs`](../scripts/cloud-migrate/seed-community-loop-v1.mjs)
- 云端路径：`/opt/ninewood/server/scripts/seed-community-loop-v1.mjs`
- 标记：`community-seed-v1`（Ledger.referenceType / Message 前缀 / ServiceCard 标题 / LoopRun.correlationId / Circle 名）
- 幂等：可重复执行；已有同标记记录会 skip

复跑：

```bash
cd /opt/ninewood/server
node scripts/seed-community-loop-v1.mjs --dry-run
node scripts/seed-community-loop-v1.mjs --limit 80
node scripts/seed-community-loop-v1.mjs
```

---

## 4. 仍偏冷 / 未全员的数据类型

| 项 | 说明 |
|----|------|
| ServiceCardEvidence | 仍近空（未在 v1 强制） |
| ActiveDemand 死池 | 仍 0 |
| VOICE/VIDEO 消息 | 仍 0 |
| AgentTask | 仍 0 |
| Short | 仍 0 |
| 真实充值通道 | 仍为模拟点数 |
| CardAttachment | 仅烟测 2 行，未按人批量发卡 |

---

## 5. 抽查（试点用户）

用户 `张师傅水电`（seed ledger 样本）：

- `/wallet/balance` 200
- `/messages/conversations` 有会话
- `/loops/runs/mine` total≥2
- `/circles/my` 有圈
- `/users/favorites` 有收藏
