# Ninewood macOS 关键业务验收

## 自动检查

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ninewood-macos.xcodeproj \
  -scheme ninewood-macos \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO
```

CI / 本地一律固定完整 Xcode（勿用 Command Line Tools 兜底）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## 非破坏性回归

1. 无 Token 启动进入登录页。
2. 有效 Token 启动直接进入发现页。
3. 云端不可达时显示重试，而不是清除有效 Token。
4. 发现列表加载后保持选中项；刷新后同 ID 仍存在时继续选中。
5. 发布表单验证标题、期望效果、金额和线下地区。
6. 切换在线需求后不得提交地区 ID。
7. 订单角色筛选不会丢失仍存在的选中订单。
8. 服务方未预付时不能标记完成。
9. 需求方待验收时仅显示结算和争议动作。
10. 打开会话只在本地递减对应未读数，不得低于零。
11. 实时消息重复 ID 不重复追加。
12. 自然回推荐无地回时只生成草稿，不自动发布。
13. 订单列表金额缺失时显示「—」，不得用 `minPrice` 冒充托管/应付。
14. PaymentSheet 未加载到 `pay-breakdown` 时禁止确认预付。
15. `CANCELLED` / `REFUNDED` 订单不得出现「评价」动作。

## 黄金路径（交易主链）

主链唯一口径（applicant 两段式，**不**走 accept-bid）：

`发布 → request → accept → pay-breakdown/prepay → complete|partial → confirm|dispute → review`

### 角色与账号

| 角色 | 用途 | 约束 |
|------|------|------|
| 需求方 (Requester) | 发布、接受申请、预付、验收/争议、评价 | 仅测试账号 |
| 服务方 (Provider) | 申请接单、标记完成/部分完成 | 仅测试账号 |

禁止用生产真实用户钱包做写路径。开发期点数为模拟货币；充值/提现不在本剧本内。

### 证据表格式（每步必填）

| 步骤 | 时间(UTC) | demandId | orderId | stage / rawStatus | isPrepaid | balance | held | ledgerΔ | 备注 |
|------|-----------|----------|---------|-------------------|-----------|---------|------|---------|------|
| … | … | … | … | … | … | … | … | … | … |

流水增量 `ledgerΔ`：本步前后 `GET /wallet/ledger` 新增条目摘要（类型、金额、关联 ID）。

### 剧本 A — 黄金路径（验收结算）

| # | 操作方 | 动作 | 期望对象状态 | 期望钱包 |
|---|--------|------|--------------|----------|
| A0 | 双方 | 记录初始 `balance` / `held` | — | 基线 |
| A1 | 需求方 | 发布需求（最低报价 > 0） | demand `OPEN`；响应含资金摘要字段 | 若发布扣托管：balance↓ held↑ |
| A2 | 服务方 | `POST …/request` 申请接单 | applicant 待处理 | 不变 |
| A3 | 需求方 | `accept/:applicantId` | 生成 order；stage≈`inProgress`；未预付 | 不变（或按服务端规则） |
| A4 | 需求方 | `GET …/pay-breakdown` | 返回 `payableNow` / `escrowHeld` / `ruleVersion` | 不变 |
| A5 | 需求方 | `POST …/prepay` | `isPrepaid=true`；服务方可履约 | balance↓（应付额） |
| A6 | 服务方 | `POST …/complete` | stage≈`waitingReview` | held 按规则变化 |
| A7 | 需求方 | `POST …/confirm` | stage≈`completed` | 服务方到账；需求方 held↓ |
| A8 | 需求方 | `POST /reviews` | 评价成功 | 不变 |

### 剧本 B — 争议分支

在 A5 之后：

| # | 操作方 | 动作 | 期望 |
|---|--------|------|------|
| B6 | 服务方 | complete | waitingReview |
| B7 | 需求方 | dispute + evidenceUrls（可空或上传） | stage=`disputed`；客户端仅 refresh |
| B8 | — | 记录 held/冻结；**不**在客户端做裁决 | 裁决属运营后台 |

### 剧本 C — 取消/退款（若服务端允许）

| # | 操作方 | 动作 | 期望 |
|---|--------|------|------|
| C1 | 需求方 | 未预付或规则允许时 `cancel` | rawStatus=`CANCELLED`；stage 映射为 `cancelled` |
| C2 | — | 核对退款入账与 ledger | 客户端不得对 REFUNDED 开放 review |

### 重要动作（人工确认门）

以下动作只能在测试账号/测试钱包执行，并按证据表记录操作前后余额和对象 ID：

- 发布需求；
- 请求接单、接受申请者；
- 预付服务费；
- 确认完成和结算；
- 部分结算；
- 提交争议；
- 删除或撤回需求；
- 取消订单。

生产账号验收必须停在最终按钮前，由用户确认或亲自执行。

### E4 证据归档

每次完整跑通后，将填写好的证据表追加到本文「E4 证据记录」或独立附件（脱敏手机号）。失败步骤回写 `docs/BUSINESS-INVENTORY.md` 对应条目证据等级。

## E4 证据记录

| 批次 | 日期 | 剧本 | 结果 | 备注 |
|------|------|------|------|------|
| e4-1784283980 | 2026-07-17T10:26:21Z | A 黄金路径 | pass | demand `9eb6642f…` order `4867aa1a…`；发布后 balance 1000000→999900 held 0→100；预付后 999895；验收后 requester held 0、provider 1000000→1000100 |
| e4-1784283980 | 2026-07-17T10:26:22Z | B 争议 | pass | order `61ed8d2c…` dispute 成功 |
| e4-1784283980 | 2026-07-17T10:26:22Z | C 取消 | pass | order `8247f631…` 未预付取消成功 |
| u-1784349366 | 2026-07-18T04:36:06Z | U1–U7 + A8（无 AI） | pass | captcha `bypass` + SMS `delivery=fallback`；demand `eb9538e5…` order `3d8836cb…` COMPLETED；review `02f2a5a1…`；dispute order `defec550…` DISPUTED；cancel `541e2c15…`；通知 2 条均带 `orderId`（可深链订单） |

可复跑脚本：

- `scripts/cloud-migrate/e4-trade-loop-smoke.sh`（交易主链；已含 A8 评价）
- `scripts/cloud-migrate/u-acceptance-no-ai.sh`（U1–U7 + A8，不含 Agent）

> **A8 评价：** 批次 `u-1784349366` 已 API E4 通过；`e4-trade-loop-smoke.sh` 已补 A8 步骤。Mac App UI 评价入口仍须手测（U5）。

## App UI 手测清单（与 API E4 并列）

当前交易主链**最高证据 = API E4**（curl）。以下为 Mac App 手工 UI 验收，通过后可升为「App UI E4」并单独建批次号。

| # | 步骤 | 期望 | API 证据（u-1784349366） | App UI |
|---|------|------|--------------------------|--------|
| U1 | 注册（fallback 模式） | 醒目「开发通道」提示；验证码自动填入；正式 SMS 时无明文 code 条 | **pass** `mode=bypass` + `delivery=fallback` | 待手测横幅文案 |
| U2 | 发现 → 需求详情 → 申请接单 | 申请成功，私信/沟通窗口可见 | **pass** request→applicant | 待手测 |
| U3 | 发布者接受申请 | 生成订单并可打开订单详情 | **pass** order 已生成 | 待手测 |
| U4 | 需求方打开 PaymentSheet | 必须加载 pay-breakdown；确认后余额/托管变化符合服务端 | **pass** payableNow=5，预付后 balance=999895 | 待手测 Sheet |
| U5 | 服务方标记完成 → 需求方验收 | 状态推进；评价入口出现（若阶段允许） | **pass** COMPLETED + A8 评价成功 | 待手测 |
| U6 | 争议提交（含可选证据） | 订单进入争议态 | **pass** DISPUTED | 待手测证据上传 UI |
| U7 | 通知列表点击 | 订单/需求/path 正确跳转；无法识别时 toast，不静默 | **pass** 通知带 `orderId`（深链订单）；生产样本暂无 demandId/path | 待手测点击 |
| U8 | Agent 写工具（如创建需求） | 弹出批准 Sheet；允许则执行，拒绝则对话留痕且无写副作用 | **跳过**（本轮不测 AI） | 待 AI 通路恢复后测 |

生产账号验收仍须停在最终写操作按钮前由用户确认。
