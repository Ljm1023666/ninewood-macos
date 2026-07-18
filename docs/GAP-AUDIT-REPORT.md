# 九木项目 · 真实落地差距深度审视报告

> **审计日：** 2026-07-18  
> **范围：** macOS 客户端仓库 `ninewood-macos` × 生产 API `tothetomorrow.com` / `8.217.208.203:/opt/ninewood`  
> **方法：** 对照 `docs/BUSINESS-INVENTORY.md`、`BUSINESS-RULE-GAPS.md`、`QA-RUNBOOK.md`；扫描 Swift 实现与测试；生产只读探测（无业务写入）；核对交易 E4 烟测档案  
> **结论口吻：** 区分「代码已接线」「路由在线」「单元契约可复验」「真实业务 E4」四级，禁止把某一级抬成下一级。  
> **验收标准：** 本报告缺陷落地判定见 [GAP-ACCEPTANCE-CRITERIA.md](GAP-ACCEPTANCE-CRITERIA.md)。

---

## 0. 一句话总判

九木 macOS 客户端已经覆盖「发现—发布—申请接单—订单履约—消息—助手—钱包只读」的**产品面宽度**，交易主链在**服务端 curl E4**上可证明闭环；但距「可对外公测的真实市场平台」仍差在：**资金进出、反滥用正式化、供给侧样本、Agent 写操作人机确认、通知深链、以及文档/证据口径的漂移**。  
换句话说：**骨架接近完成，血肉与公信力基础设施未齐。**

---

## 1. 审计坐标系

### 1.1 证据等级（沿用清单定义）

| 等级 | 能证明什么 | 不能证明什么 |
|------|------------|--------------|
| **E1** 静态代码 | 有入口、有调用路径 | 线上能用 |
| **E2** 路由在线 | 路径存在 / 鉴权挡板存在 | 授权后业务结果正确 |
| **E3** 自动测试 | 领域规则 / DTO 契约可回归 | UI、Socket、真实资金 |
| **E4** 业务验收 | 测试账号写路径前后状态+钱包 | 全量用户场景与运营闭环 |

### 1.2 本轮实采证据

| 来源 | 结果摘要 |
|------|----------|
| `swift test`（固定 Xcode） | **28** 项领域/DTO 测试通过（非清单旧称 22） |
| 生产 `/health/services` | `degraded`：Express/PG/Redis online；语义分类器 offline；Vite offline（预期） |
| 生产 `/captcha` | `siteKey=""`，`mode=bypass` |
| 生产 SMS/hCaptcha env | 腾讯云 SMS / hCaptcha **均未配置**；`CAPTCHA_DEV_BYPASS=1` |
| 公开样本 | 需求搜索/活跃池有数据；**死池 0**；**服务卡搜索 []**；**福利列表 0** |
| 受保护路由 | `/orders` `/auth/me` `/wallet/balance` `/messages/conversations` `/agent/conversations` → **401**（路由在） |
| 资金契约代码 | 生产已存在 `buildMoneySummary`（demand create / order list+detail） |
| 交易 E4 档案 | `QA-RUNBOOK` 批次 `e4-1784283980`：黄金路径 / 争议 / 取消 **pass**（curl 脚本，非 SwiftUI） |
| accept-bid | 生产仍返回废弃提示，要求走 `accept/:applicantId` |

---

## 2. 落地成熟度总表（域 × 证据）

| 域 | 产品期望 | 客户端 | 生产契约 | 最高证据 | 与「真实落地」差距 |
|----|----------|--------|----------|----------|-------------------|
| 登录会话 | 稳定鉴权 | 完整 | JWT+cookie | E2 | 低 |
| 注册反滥用 | 短信+人机 | 有 UI，bypass token | siteKey 空、SMS 未配 | E2+临时 E4 | **高（公测阻断）** |
| 发现/需求读 | 可浏览撮合 | 完整 | 有样本 | E2 | 中（缺附近筛选/分页体验） |
| 发布+托管 | 全额托管可验证 | 完整 | money summary 已回 | **API E4** | 中（缺 App UI E4 自动化） |
| 两段式成单 | request→accept | 完整 | 路由在 | API E4 | 中（沟通窗口缺真人 E4） |
| 应标/抢单 | 意向或废弃 | UI 保留+文案收口 | snatch/bid 仍在 | E1/E2 | 中（死池无样本；用户易混淆） |
| 预付/履约/争议 | 资金可审计 | PaymentGate+证据上传 | pay-breakdown 在 | **API E4** | 中（争议后无客户端裁决；partial 余量体验弱） |
| 钱包进出 | 充值/提现 | **占位** | 无正式支付通道 | E1 | **极高** |
| 消息实时 | Socket 可靠 | 有连接与去重 | 路由在 | E1/E2 | **高**（无 Socket E4） |
| 通知深链 | 对象可跳转 | 仅 orderId | — | E1 | **高** |
| Agent 对话 | 可读可导航 | SSE+navigate 白名单 | approval 默认 | E1/E2 | **高**（无批准卡） |
| 服务卡市场 | 有供给 | 有搜索 UI | **空数组** | E2 空 | **高（供给为零）** |
| 福利 | 可领可奖 | 领取路径已修 | **列表空** | E2 空 | 高（无法证领取） |
| 圈子 | 私人圈 | Scope Lock 已收 | 公开空 | E1/E2 | 中（缺成员管理/资源） |
| 自然回 | 可执行可验证 | offerings+capabilities | 有数据 | E2 | 中（运行写路径无 E4） |
| 运维可观测 | 错误可追踪 | — | **无 Sentry DSN** | E2 | 高（生产告警空白） |
| 文档一致性 | 清单=现实 | — | — | — | **高（多处口径过期）** |

---

## 3. 分域精细差距

### 3.1 交易主链（相对最强，但仍有「证据分层」问题）

**已落地（可复核）**

- 客户端：`DemandDraft` → multipart 发布；`request` / `accept`；`pay-breakdown` 强制门控；complete / partial / confirm / dispute(+evidence) / cancel / review；`OrderActionPolicy` + `OrderPaymentGate`。
- 生产：`buildMoneySummary` 已挂 create/list/detail；E4 烟测记录发布后 `balance 1000000→999900, held 0→100`，预付 −5，验收后服务方 `+100`，争议与取消均 pass。

**差距明细**

| ID | 差距点 | 现状 | 影响 | 建议优先级 |
|----|--------|------|------|------------|
| T-GAP-01 | E4 是 curl 不是 App | `e4-trade-loop-smoke.sh` 不经 SwiftUI | 「客户端交易已 E4」表述过强 | P1 文档纠偏 + 可选 UI 手测清单 |
| T-GAP-02 | 评价步骤 A8 未进烟测 | 剧本含 review，批次未记 | 评价链路证据缺失 | P2 |
| T-GAP-03 | partial 完成未进烟测 | 仅 complete/confirm | 部分结算余量需求未证 | P1 |
| T-GAP-04 | 争议后客户端只 refresh | 无调解/撤诉 UI | 用户卡在 DISPUTED | P2（依赖运营后台） |
| T-GAP-05 | 列表金额缺字段时显示 0/— | mapper 已禁 minPrice 付款回退 | 列表可读性仍弱 | P2 |
| T-GAP-06 | inventory §2.17/§1 仍写「无 E4」 | 与 §8 已划掉、QA 记录冲突 | 团队误判进度 | **P0 文档** |

### 3.2 资金与「市场货币」真实性

| ID | 差距点 | 证据 | 影响 |
|----|--------|------|------|
| M-GAP-01 | 无在线充值 | `WalletView` 明确「开发期暂不支持」 | 点数耗尽即交易停摆 |
| M-GAP-02 | 无提现 | Service 无方法 | 无法兑现「平台担保交易」对外叙事 |
| M-GAP-03 | 默认 100 万点 | E4 新注册用户 balance=1000000 | 模拟经济，非真实稀缺 |
| M-GAP-04 | `/transactions/*` 无 UI | inventory §3 | 无法从客户端审计历史结算单 |
| M-GAP-05 | BR-001/002 文档已关，但产品策略充值仍开 | `BUSINESS-RULE-GAPS` | 规则关闭 ≠ 资金产品完成 |

**判定：** 交易闭环在「模拟点数宇宙」内已通；在「真实法币/支付」宇宙内 **未启动**。

### 3.3 身份与反滥用（公测硬门槛）

| ID | 差距点 | 生产实况 | 客户端 | 风险 |
|----|--------|----------|--------|------|
| A-GAP-01 | hCaptcha 未配置 | `siteKey=""` `mode=bypass` | `unconfigured-bypass` token | 注册可被脚本刷 |
| A-GAP-02 | 短信未配置 | 无 TENCENT_SMS_* | 验证码回传并自动填入 | 验证码等于明文 API 字段 |
| A-GAP-03 | 登录无验证码 | — | 仅手机号+密码 | 撞库/爆破面暴露（有限流但非人机） |
| A-GAP-04 | 无头像/封面上传 UI | inventory 仍列差集 | 账号人格化弱 | 体验 |
| A-GAP-05 | 注册已实现但 inventory §3 仍写「账号｜注册…无」 | 文档过期 | 排期重复/遗漏 | 文档 |

**判定：** 注册功能「能用」，但**不能**称为安全上线能力。

### 3.4 撮合供给（空市场风险）

| ID | 能力 | 生产样本（2026-07-18） | 客户端 | 差距 |
|----|------|------------------------|--------|------|
| S-GAP-01 | 公开服务卡 | `service-cards/search` → **[]** | 有「市场」分段 | **零供给** |
| S-GAP-02 | 死池 | `demands/dead` → **0** | 有 UI/抢单入口 | 无法验证 snatch |
| S-GAP-03 | 福利任务 | `welfare/demands` → **0 items** | 领取路径已修 | 无法 E4 领取 |
| S-GAP-04 | 发现列表 | 有数据 | 无筛选/定位/分页加载 | 体验与「附近」名实不符 |
| S-GAP-05 | `/tags` 体量大且成交统计多为 0 | tags 响应极大 | 若展示 totalCompleted 易造假象 | K-11 仍开 |
| S-GAP-06 | 服务卡编辑字段 | — | 硬编码 OFFLINE/ONSITE 等 | 编辑器不完整（§8 P2） |

**判定：** 需求侧有流量样本，**服务侧与福利侧接近空城**；产品演示易偏「只有需求没有接单供给」。

### 3.5 消息与协作

| ID | 差距点 | 现状 | 证据缺口 |
|----|--------|------|----------|
| MSG-GAP-01 | Socket E4 | 有 `ChatRealtime`、重连字段、本地去重 | 无断线重连/乱序/去重压测记录 |
| MSG-GAP-02 | 通知深链 | 仅 `orderId` → 订单详情 | 需求/会话/圈子/福利不可达 |
| MSG-GAP-03 | 群聊实时 | UI 有 merge 段 | 成员资料与实时弱，无 E4 |
| MSG-GAP-04 | 卡片种类 | 未知类型软失败 | 「暂不支持打开此类卡片」 |
| MSG-GAP-05 | 沟通窗口 | 倒计时+延期已接 | 缺真人双端 E4（D-08） |
| MSG-GAP-06 | 推送偏好 | 设置非完整 `/pushes/preferences` | Service/UI 缺 |

### 3.6 Agent（差异化能力 vs 落地）

| ID | 差距点 | 现状 | 影响 |
|----|--------|------|------|
| AG-GAP-01 | 写工具批准卡 | 客户端固定 `accessMode: "approval"`；**无确认 Sheet** | 写工具在云侧挂起/拒绝，用户无操作面 |
| AG-GAP-02 | 读工具不落地 | search/list/detail 结果停在聊天 | 「助手能办事」感知弱，只能聊天+导航 |
| AG-GAP-03 | 导航白名单 | 管理/行情路径拒绝并提示 | 正确但暴露产品面缺口 |
| AG-GAP-04 | Agent 任务页 | A-07 未实现 | 云端任务无法在客户端管理 |
| AG-GAP-05 | 数据保真 | region/tag fidelity 有约束 | `/regions` 公开仅部分；provider_region 仍 stub |
| AG-GAP-06 | 语义分类器 offline | health degraded | Agent/搜索相关能力可能降级 |

**判定：** Agent 是「受控导航型聊天」，不是「可确认写操作的桌面执行器」。

### 3.7 圈子 / 认证 / 自然回

| ID | 差距点 | 说明 |
|----|--------|------|
| CIR-GAP-01 | 成员角色变更/移除/资源上传 | Service 能力不全或无 UI |
| CIR-GAP-02 | 公开圈路由仍在生产 | 客户端已藏入口（Scope Lock OK），但空公开数据仍在 |
| CERT-GAP-01 | 无认证账号 E4 | 申请/升级未用真实达标路径验收 |
| CERT-GAP-02 | snatch-status 无页 | `UserService.snatchStatus` 闲置 |
| LOOP-GAP-01 | 运行写路径无 E4 | offerings/capabilities 只读证据强 |
| LOOP-GAP-02 | `runs?demandId=` 无产品入口 | inventory §8 P2 |

### 3.8 工程质量与可回归性

| ID | 差距点 | 数字/事实 |
|----|--------|-----------|
| Q-GAP-01 | 测试面极窄 | **28** 个 XCTest，全是 Publish/OrderPolicy/DTO；无 APIClient、FeatureModel、UI、Socket |
| Q-GAP-02 | 无 CI workflow | 仓库无 `.github`；仅有 `scripts/test-with-xcode.sh` |
| Q-GAP-03 | Feature Model 覆盖不均 | Orders/Discover/Messages 有；Wallet/Circles/Agent/Welfare 仍偏 View→Service |
| Q-GAP-04 | 生产无 Sentry | `.env` 无 `SENTRY_DSN` | 线上错误不可观测 |
| Q-GAP-05 | OpenAPI 不可消费 | `/api-docs` 返回前端 HTML | 契约发现困难 |
| Q-GAP-06 | 限流/代理噪音 | 历史有 `X-Forwarded-For` / trust proxy 告警类问题 | 运维卫生 |

### 3.9 文档与真实状态漂移（审计发现的「元差距」）

以下条目说明：**仓库文档本身已落后于 2026-07-17 交易闭环落地**，若不修正会持续误导排期。

| 文档位置 | 过时表述 | 真实状态（2026-07-18） |
|----------|----------|------------------------|
| inventory 文首「最高只做到 E2/E3」「写路径仍无 E4」 | 否认 E4 | QA 已有交易 E4 批次；资金摘要已上生产 |
| §2.17 发布/订单行「无测试钱包 E4」 | 否认 E4 | curl E4 已跑通 |
| §2.18 K-01/K-02「待 E4」 | 待办 | E4 已部分覆盖 |
| §3「账号｜注册…无」 | 无注册 | `RegisterView` + 生产 register fallback 已存在 |
| §6「22 tests」 | 旧数 | 现 **28** |
| O-11「缺失时 minPrice 列表回退」 | 旧 mapper | 已改为缺字段展示「—」/不驱动付款 |

---

## 4. 「计划完成定义」对照（交易闭环计划）

对照 `trade_loop_closure` 完成定义逐条验收：

| 完成定义 | 状态 | 备注 |
|----------|------|------|
| 黄金路径 + 争议 E4 成功且有钱包证据 | **满足（API）** | 批次 e4-1784283980 |
| 客户端付款/列表不以本地费率或 minPrice 驱动资金决策 | **满足** | PaymentGate + mapper |
| 领域/契约测试覆盖资金 DTO 与动作门控；固定 Xcode 下绿 | **满足** | 28 tests + test-with-xcode.sh |
| Inventory §8 P0 与 BR-001/002 关闭或降级充值残留 | **部分满足** | BR 已关；inventory 文首/§2.17 **未全面同步** |

---

## 5. 与「可公测产品」的关键差距分层

### P0 — 不解决则不宜对陌生用户开放写路径

1. **正式反滥用：** 配置 hCaptcha + 短信（或等价），关闭验证码回传与 bypass token。  
2. **文档纠偏：** 统一 E4/注册/测试数/金额 mapper 口径，避免「以为没做」或「以为做完 App E4」。  
3. **生产可观测：** Sentry（或境内替代）+ 关键错误聚合。  

### P1 — 不影响演示，但影响「像真市场」

1. **钱包产品策略拍板：** 继续模拟点 vs 接入支付；至少提供受控调账运营流程文档。  
2. **供给冷启动：** 服务卡公开样本、福利任务样本、死池样本（否则市场/福利/抢单都是空壳）。  
3. **Agent 写操作批准卡**（或明确产品降级为只读+导航）。  
4. **通知统一深链协议**（demand/message/circle/welfare）。  
5. **Socket 实时 E4**（重连、去重、双端一致性）。  
6. **partial 完成 E4** 与评价步骤补档。  

### P2 — 体验与完备性

1. 发现筛选/附近定位/分页。  
2. 服务卡编辑字段对齐 ADR。  
3. 推送偏好、`snatch-status` 页、`loops/runs?demandId=` UI。  
4. `/transactions` 历史、`/tag-stats` 展示策略。  
5. Feature Model 继续下沉 + CI 真正接入。  
6. 头像/封面上传。  

---

## 6. 风险叙事（给决策者）

1. **最危险的误解：** 「交易闭环 E4 已完成」被理解成「用户在 Mac App 里已经完整验过」。实际是 **服务端脚本宇宙** 验过。  
2. **最危险的技术债：** captcha/SMS bypass 留在 **NODE_ENV=production**。这是安全债，不是体验债。  
3. **最危险的产品空心化：** 服务卡/福利/死池为零供给时，客户端「市场」「福利」「抢单」入口会制造虚假完整感。  
4. **最危险的差异化落空：** Agent 无批准卡时，写工具能力矩阵无法转化为桌面产品能力。  

---

## 7. 建议的下一步（不扩 scope）

若只选一件继续做深度落地，按杠杆排序：

1. **安全正式化（captcha+SMS）** — 解锁可信注册增长；  
2. **inventory 全文与证据等级刷新** — 让后续排期不再踩元数据坑；  
3. **Agent 批准卡 MVP** — 把唯一差异化能力接到人机回路；  
4. **供给样本播种（服务卡/福利）** — 让「市场」不再空转。  

---

## 8. 附录 · 本轮探测原始要点

```
health: degraded (classifier offline, vite offline)
captcha: {"siteKey":"","mode":"bypass"}
SMS/hCaptcha keys: absent
dead pool: 0 | service-cards: [] | welfare items: 0
protected routes: 401
buildMoneySummary: present in settlement/demand/order services
accept-bid: deprecated message on order router
swift test: 28 passed
E4 batch: e4-1784283980 A/B/C pass (API smoke)
```

### 关键代码锚点

| 主题 | 路径 |
|------|------|
| 付款门控 | `ninewood-macos/Domain/Orders/OrderActionPolicy.swift` |
| PaymentSheet | `ninewood-macos/Views/Orders/OrdersViews.swift` |
| 注册/bypass | `Views/Auth/RegisterView.swift`，`API/Services/MiscServices.swift` |
| 钱包占位 | `Views/Wallet/WalletView.swift` |
| Agent 流 | `API/Services/AgentService.swift`，`Views/Agent/AgentChatView.swift` |
| E4 脚本 | `scripts/cloud-migrate/e4-trade-loop-smoke.sh` |
| 验收档案 | `docs/QA-RUNBOOK.md` |

---

*本报告描述差距与证据。落地修复与 pass/fail 判定见 [GAP-ACCEPTANCE-CRITERIA.md](GAP-ACCEPTANCE-CRITERIA.md)。*
