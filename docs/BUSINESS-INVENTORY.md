# 九木 macOS 客户端 — 业务能力清单

> **范围：** `ninewood-macos` 原生 SwiftUI 客户端（权威状态来自云端 API）  
> **调研基准：** 2026-07-17  
> **方法：** 对照侧栏/个人中心路由、`Views/`、`API/Services/`、`Data/Repositories/`、`Domain/`、`Features/`、Swift 测试、`ninewood-docs` 现行 ADR/开发主线、`scripts/cloud-migrate/agent-router/`，并对生产 API 执行无凭证只读/无副作用路由探测  
> **非范围：** Windows Electron 客户端差集、云端内部未暴露 API（除 Agent 能力矩阵外）

## 状态定义

| 状态 | 含义 |
|------|------|
| **已实现** | 有可用 UI，主路径已接 API（或明确的本地静态内容），且没有已知阻断性缺口 |
| **部分实现** | 主路径存在，但关键子能力、数据解释或产品契约仍不完整 |
| **需验证** | 存在具体契约疑点：认证后响应无法由现有 Fixture 证明，或现行文档、客户端与生产路由互相冲突 |
| **仅占位** | 有入口或按钮，但明确提示不可用 / 不发起真实业务写操作 |
| **未实现** | 云端或客户端 Service 已有能力，但无对应 macOS UI（或 UI 为空壳） |

## 证据等级

业务状态与证据强度分开记录。`已实现` 不自动等于“已在生产账号完成交易验收”。

| 等级 | 证据 | 能证明什么 |
|------|------|------------|
| **E1 静态代码** | View、Feature Model、Repository、Service、DTO | 客户端存在入口与调用路径 |
| **E2 路由在线** | 生产无凭证 GET 返回 200，或受保护路由返回统一 401 | 路由当前存在；不能证明授权后的业务结果 |
| **E3 自动测试** | Swift 单测 / Fixture / 云端测试记录 | 被覆盖的规则或解码契约可重复验证 |
| **E4 业务 E2E** | 测试账号、测试钱包、操作前后对象与余额记录 | 真实业务闭环可用 |

本轮最高证据含：**交易主链 API E4**（见 `docs/QA-RUNBOOK.md` 批次 e4-1784283980，curl 烟测）；
领域/DTO **E3**（30 项）；公开路由 **E2**。  
**尚未**完成：Mac App UI 自动化 E4、正式 captcha/SMS、充值/提现、Socket E4。

> 证据分层见 [GAP-AUDIT-REPORT.md](GAP-AUDIT-REPORT.md) 与验收标准 [GAP-ACCEPTANCE-CRITERIA.md](GAP-ACCEPTANCE-CRITERIA.md)。

### 本轮已修复

| 清单项 | 处理 |
|--------|------|
| K-03 / WEL-02 福利领取 404 | 客户端改为 `POST /welfare/claim/:demandId`（与生产一致） |
| K-02 / O-03 付款本地推导 | 生产新增 `GET /orders/:id/pay-breakdown`；PaymentSheet 必载服务端分项 |
| K-04 争议假证据承诺 | 生产 dispute 接入 `rejectWithComplaint` + `evidenceUrls`；macOS 支持图片上传/URL；文案改为「提交争议」 |
| K-01 / D-02 deposit 未解码 | `DemandDetailDTO` 接入 `deposit`/`amountEstimate`/`mediaUrls`/`lifecycleStage` 并展示 |
| K-05 timeLimit Int | `OrderDemandDTO.timeLimit` 改为 `FlexibleDateValue`，兼容 ISO 与遗留 Int |
| K-06 amountEstimate | 详情 Mapper 消费 `amountEstimate` |
| K-07 mediaUrls | 详情附件区展示 |
| K-08 公开圈 Scope Lock | 移除公开圈 Tab，仅「我的」私人圈 |
| K-13 帮助文案 | 部分完成说明改为 newPrice/服务端结果口径 |
| BR-002 文档 | `BUSINESS-RULE-GAPS.md` 与实现同步 |
| D-08 沟通窗口 | 生产会话响应增加沟通上下文；macOS 显示倒计时，发布者可延长 5 分钟 |
| M-06 删除冻结需求 | Repository + 二次确认 UI 已接；退款结果以钱包流水为准 |
| MSG-05 通知 | 分页、已读、多对象深链（订单/需求/path） |
| MSG-07/08 卡片消息 | 历史 API 返回 snapshot；macOS 可发送并渲染需求卡/服务卡 |

1. **客户端覆盖面广，验证深度分层。** 登录、公开需求、卡池、自然回目录具备
   线上只读证据；交易写路径已有 **API E4**（curl），尚无 Mac App UI 自动化 E4。
2. **资金：付款强制 pay-breakdown；列表优先服务端 escrow/serviceFee。** 缺字段展示「—」，
   不以 `minPrice` 驱动付款。充值/提现仍为产品策略占位。
3. **福利领取路径已与生产对齐**；列表为空时仍无法做领取样本 E4。
4. **争议已支持原因 + 可选证据**；完整调解流程仍依赖管理员后台。
5. **圈子已按初期 Scope Lock 收口为私人圈。**
6. **Agent 具备受控导航**；写工具批准卡见本轮修复（`approve-tool`）。
7. **注册已实现**；正式 captcha/SMS 未配置时走显式 fallback（须 `AUTH_SMS_FALLBACK=1`）。

## 线上基线快照

2026-07-17 对 `https://tothetomorrow.com/api` 进行无 Token、无业务写入探测：

| 探测项 | 结果 | 解释 |
|--------|------|------|
| `/health/services` | 200，整体 `degraded` | Express/PostgreSQL/Redis 在线；语义分类器和开发 Vite 服务离线 |
| `/captcha` | 200，`siteKey` 为空 | 路由存在，但当前没有可供登录页使用的验证码配置 |
| `/regions` | 200，24 条二级地区 | 当前公开响应不是 Agent 清单所称的完整 75 条目录，需区分接口过滤与数据总量 |
| `/tags` | 200，1188 条；`totalCompleted` 全为 0 | 标签目录可用，统计字段不能作为真实成交行情 |
| `/tag-stats` | 200，有非零聚合样本 | 独立统计路由存在；按 Agent fidelity 只能作有限覆盖趋势 |
| `/certification/providers`、`/providers/search`、`/providers/certified` | 200，有样本 | 服务者检索在线；地域维度仍按 fidelity 标为 stub |
| `/demands/search`、`/demands/:id` | 200，有真实列表/详情结构 | `deposit`、`lifecycleStage`、`mediaUrls` 已接入客户端详情 |
| `/demands/active`、`/demands/dead` | 200 | 活跃池有数据；探测时死池为空 |
| `/service-cards/search` | 200，空数组 | 路由存在，不能证明公开供给已形成 |
| `/circles/public`、`/circles-enhanced` | 200，空数组 | 路由存在，公开圈当前无样本 |
| `/welfare/demands` | 200，空列表 | 福利展示路由存在；无法证明领取闭环 |
| `/loops/offerings` | 200，有 EARTH offering | 地回公开目录可用 |
| `/loops/capabilities` | 200，16 项且 endpoint 均 ONLINE | 天回能力数据存在，macOS 已接只读目录 UI |
| 付款分项、福利领取、通知已读等受保护路由 | 401 | 以假 ID/空凭证探测，路由存在且未越过鉴权；不能证明认证后业务结果 |
| 订单、消息、钱包、收藏、Agent 会话等 | 401 | 受保护路由存在；未完成认证后响应/E2E |
| `/api-docs`、`/openapi.json` | 返回前端 HTML | 生产没有可直接消费的 OpenAPI 入口 |

---

## 1. 产品入口地图

### 1.1 侧栏（`MainShellView` / `SidebarItem`）

| 入口 | 业务名 | 落地 View |
|------|--------|-----------|
| discover | 发现 | `DiscoverView` |
| cardPool | 卡池 | `CardPoolView` |
| publish | 发布 | `CreateDemandView` |
| circles | 圈子 | `CirclesView` |
| loops | 自然回 | `NaturalLoopWorkspaceView` |
| searchPeople | 找人 | `FindPeopleView` |
| messages | 消息 | `MessagesView` |
| cert | 认证 | `CertCenterView` |
| help | 帮助 | `HelpView` |
| profile | 我的 | `ProfileView` |

### 1.2 「我的」二级导航（`ProfileView`）

| 分组 | 子项 |
|------|------|
| 交易 | 订单 · 我的需求 · 我的应标 · 钱包与托管 |
| 服务与认证 | 服务卡 · 认证中心 · 认证检索 |
| 社交 | 关注 · 收藏 · 通知 · 我的回 · 福利中心 |
| 其他 | 九木助手 · 设置 |

### 1.3 会话壳层

| 能力 | 状态 | 说明 |
|------|------|------|
| 启动引导 / Token 恢复 | 已实现 | `ContentView` + `AuthSession` / `AppSession.bootstrap` |
| 登录页 | 已实现 | 手机号 + 密码 → `/auth/login` |
| 云端不可达保留 Token | 已实现 | `serviceUnavailable`，可重试 |
| 退出登录 | 已实现 | 侧栏底部 → `/auth/logout` |
| 未读角标 | 已实现 | 侧栏「消息」+ `InboxState` |
| 账号注册 | 已实现 | 登录页「注册」→ `/auth/send-code` + `/auth/register`；短信/hCaptcha 未配置时走临时 fallback |
| 图形验证码 | 未实现 | `/captcha` 在线但 `siteKey=""`；登录页未接入，当前也没有可用站点配置 |

---

## 2. 分域业务清单

### 2.1 发现与需求撮合

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| D-01 | 附近/活跃需求列表 | 已实现 | `DiscoverFeatureModel` → `DemandRepository.discover` → `/demands/search` | E2：生产 200 有数据；当前列表没有筛选、分页加载或明确“附近”定位输入 |
| D-02 | 需求详情展示 | 已实现 | `DemandDetailView` + `DemandDetailFeatureModel`；DTO/Mapper 消费 `deposit`、`mediaUrls`、`lifecycleStage`、`amountEstimate` | E2：生产详情可读；附件区和托管金额已展示 |
| D-03 | 请求接单 | 已实现 | Sheet → `/demands/:id/request` | — |
| D-04 | 卡池应标 | 部分实现 | Sheet → `/demands/:id/bid` | **语义已收口**：应标=意向报价，不成单；正式成单仅 applicant → accept |
| D-05 | 收藏 / 取消收藏 | 已实现 | `/users/favorites/:id`；列表在「我的 → 收藏」 | — |
| D-06 | 刷新单条详情 | 已实现 | `/demands/:id` | — |
| D-07 | 15 分钟可见窗口 / 生命周期 | 部分实现 | DTO/Mapper 已保留 `lifecycleStage`；详情兼容 `visibleUntil/expireAt`，列表有倒计时与状态 Chip | 列表状态仍主要由 `expireAt` 和申请人数推导，尚未完整呈现冻结、满员、沟通中阶段 |
| D-08 | 5 分钟沟通资格 | 已实现 | 会话响应返回 communication；消息页倒计时；`extend-comm` 延长 5 分钟 | 缺测试账号 E4 |

### 2.2 发布需求

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| P-01 | 发布表单 | 已实现 | 标题、期望效果、金额、时限、人数、标签、线上/线下、地区、图片附件 | — |
| P-02 | 领域校验与命令组装 | 已实现 | `DemandDraft` / `DemandPublishCommand` + 单测 | — |
| P-03 | 提交发布 | 已实现 | `DemandPublishRepository` multipart `POST /demands` + 幂等键 | — |
| P-04 | 托管金额披露 | 已实现 | 发布文案 + 创建响应 `depositRequired/ruleVersion/...` + 详情 `deposit` | E4 已验收发布扣托管 |
| P-05 | 自然回人工兜底预填 | 已实现 | 无地回时打开草稿 Sheet，**不自动发布** | — |

### 2.3 卡池

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| C-01 | 进行中卡池 | 已实现 | `/demands/active` + 详情 `poolMode: .activePool` | E2：生产 200 且有样本 |
| C-02 | 死池 | 已实现 | `/demands/dead` + `poolMode: .deadPool` | E2：生产 200，但探测时为空，无法验证详情/抢单样本 |
| C-03 | 死池抢单 | 部分实现 | `/demands/:id/snatch` | 路由仍在；UI 标明遗留入口，**不**作为成单主链；正式成单仍走 applicant |
| C-04 | 快捷打开我的服务卡 | 部分实现 | Sheet → `MyServiceCardsView` | 只读管理入口，非卡池内公开浏览 |
| C-05 | 抢单额度查询 | 未实现 | `UserService.snatchStatus` → `/users/snatch-status` | 认证中心展示 `snatchCredits`，无独立额度页 |

### 2.4 我的需求 / 应标

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| M-01 | 我发布的需求列表 | 已实现 | `/demands/my` | — |
| M-02 | 查看申请人 | 已实现 | `/demands/:id/applicants-v2` | — |
| M-03 | 接受 / 拒绝申请人 | 已实现 | `/accept/:applicantId`、`/reject/:applicantId` | 接受后提示将生成订单 |
| M-04 | 撤回需求 | 已实现 | `/demands/:id/withdraw` | — |
| M-05 | 查看应标列表 | 部分实现 | `/demands/:id/bids` 只读展示报价/状态 | **不补 accept-bid**；文案已说明不可直接成单 |
| M-06 | 删除需求 | 已实现 | 冻结需求显示永久删除；二次确认 → `DELETE /demands/:id` | 服务端仅允许 FROZEN；退款以钱包流水为准 |
| M-07 | 我的应标记录 | 已实现 | `/demands/my-applications` → 可进详情 | — |

### 2.5 订单与结算

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| O-01 | 订单列表 + 角色/阶段筛选 | 已实现 | `OrdersFeatureModel` → `/orders` | `OrderDemandDTO.timeLimit` 已用 `FlexibleDateValue` 兼容 ISO 与遗留 Int；无认证样本 E4 |
| O-02 | 订单详情 | 已实现 | `OrderDetailFeatureModel` | 详情共用已固化的订单 DTO；列表摘要缺分项时明确保持“未确认” |
| O-03 | 预付 5% 服务费 | 已实现 | `PaymentSheet` 必须先取 `GET /orders/:id/pay-breakdown`，再调用 `/prepay` | 假 ID 无凭证探测返回 401；无测试钱包 E4，预览失败时客户端禁止确认 |
| O-04 | 服务方标记完成 | 已实现 | 需已预付；`/orders/:id/complete` | — |
| O-05 | 部分完成结算 | 已实现 | `PartialCompleteSheet` → `/orders/:id/partial` | 可生成剩余需求 ID 提示 |
| O-06 | 需求方验收结算 | 已实现 | `/orders/:id/confirm` + breakdown 展示 | — |
| O-07 | 争议 / 拒绝付款 | 已实现 | `RejectEvidenceSheet` → 证据图片上传/URL → `/orders/:id/dispute` | 请求携带 `evidenceUrls`；无争议样本与管理员处理 E4 |
| O-08 | 取消订单 | 已实现 | `/orders/:id/cancel` | — |
| O-09 | 评价 | 已实现 | `ReviewOrderSheet` → `POST /reviews` | — |
| O-10 | 动作门控 | 已实现 | `OrderActionPolicy`（可单测） | 最终鉴权仍在云端 |
| O-11 | 金额展示 | 已实现 | `OrderMapper` 优先 `escrowAmount/serviceFee/remainingPay`；缺失显示「—」 | 付款只认 pay-breakdown |

**`OrderActionPolicy` 允许动作摘要：**

| 角色 × 阶段 | 允许动作 |
|-------------|----------|
| 需求方 × 进行中 × 未预付 | 预付、取消 |
| 需求方 × 进行中 × 已预付 | 取消 |
| 服务方 × 进行中 × 已预付 | 标记完成、部分完成 |
| 需求方 × 待验收 | 验收结算、争议 |
| 任意 × 已完成 | 评价 |
| 任意 | 刷新 |

### 2.6 钱包

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| W-01 | 余额 / 托管中摘要 | 已实现 | `/wallet/balance` | — |
| W-02 | 流水账本分页 | 已实现 | `/wallet/ledger` | — |
| W-03 | 在线充值 | 仅占位 | 按钮弹出 Alert | 文案：「开发期暂不支持在线充值，请联系管理员调账」 |
| W-04 | 提现 | 未实现 | 客户端无相关 Service/UI | — |

### 2.7 消息与通知

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| MSG-01 | 会话列表 | 已实现 | `/messages/conversations` | — |
| MSG-02 | 1:1 发收消息 | 已实现 | `/messages/:userId`、`/messages/send` | — |
| MSG-03 | Socket.IO 实时 | 部分实现 | `ChatRealtime`；inbox epoch 触发刷新 | 私信 ID 去重；无连接状态 UI、重连失败反馈或真实 Socket E2E 记录 |
| MSG-04 | 未读数 | 已实现 | `/messages/unread-count` | — |
| MSG-05 | 系统通知列表 | 已实现 | 分页、未读态、单条/全部已读；带 orderId 可打开订单 | 其他业务对象仍待统一深链协议 |
| MSG-06 | 合并群聊 | 已实现 | 消息页「群聊」分段：列表、新建（关注联系人）、收发消息 | 无群聊样本 E4；成员资料与实时推送未接 |
| MSG-07 | 卡片附件消息 | 已实现 | 聊天附件入口可选我的需求/服务卡；`POST /messages/card-attachment` | 无测试账号 E4 |
| MSG-08 | 卡片气泡渲染 | 已实现 | 渲染需求卡/服务卡；点击深链打开需求详情或服务卡详情 | 暂无卡片点击深链 E4 |

### 2.8 自然回

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| L-01 | 意图推荐 | 已实现 | `/loops/recommend` via `NaturalLoopRepository` | UI 以地回人工兜底为主路径 |
| L-02 | 运行 offering | 已实现 | `/loops/offerings/:id/run` | — |
| L-03 | 我的运行 inbox | 已实现 | `/loops/runs/mine` | Profile「我的回」同域 |
| L-04 | 运行详情 / 事件 / 重试验证 | 已实现 | detail、events、`retry-verification` | — |
| L-05 | 人工协作草稿 | 已实现 | humanFallback → `CreateDemandView` Sheet | 不自动发布 |
| L-06 | 跳转九木助手 | 已实现 | Sheet `AgentChatView(initialPrompt:)` | — |
| L-07 | 天回能力目录 | 已实现 | 自然回工具栏「系统能力」→ `LoopService.heavenCapabilities` | E2：生产返回 16 项且 endpoint 均 ONLINE；目录只读，不把能力暴露为人工执行按钮 |
| L-08 | 按需求查 runs | 未实现 | `LoopService.runs(demandId:)` | 无独立入口 |

### 2.9 圈子

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| CIR-01 | 我的私人圈 | 已实现 | 圈子页只调用 `/circles/my`，公开圈 Tab 已移除 | 符合初期私人圈 Scope Lock；公开 API 存在但不构成当前客户端入口 |
| CIR-02 | 创建 / 邀请码加入 | 已实现 | `POST /circles`、`/join-by-code` | 私人圈主链完整；帮助中心文案已与 Scope Lock 对齐 |
| CIR-03 | Hub 概览 / 成员 / 资源 / 动态 | 已实现 | hub/home、members、resources、activities | — |
| CIR-04 | 圈子分析 | 已实现 | `/circles/:id/analytics` | — |
| CIR-05 | 管理：公告 / 邮件邀请 / 心跳 | 已实现 | announcements、invites、heartbeat（管理员） | — |
| CIR-06 | 成员 / 资源管理 | 部分实现 | 成员只读、资源下载 | 无成员角色调整、移除、资源上传/删除；Hub 更接近浏览器而非完整管理台 |

### 2.10 找人与社交关系

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| U-01 | 昵称搜索 | 已实现 | `/users/search` | — |
| U-02 | 认证服务者搜索 | 已实现 | `/certification/providers`（找人 Tab + Profile 认证检索） | E2：生产 200 有样本；与 `/providers/search`、`/providers/certified` 是并行契约 |
| U-03 | 用户资料 | 已实现 | `/users/:id` | — |
| U-04 | 关注 / 取消关注 | 已实现 | `/users/:id/follow` | — |
| U-05 | 关注 / 粉丝列表 | 已实现 | following / followers | — |
| U-06 | 收藏需求列表 | 已实现 | `/users/favorites` | — |
| U-07 | 按标签搜用户 | 部分实现 | `searchByTags` 在认证检索兜底路径使用 | 非独立产品页 |

### 2.11 认证

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| CERT-01 | 认证状态 | 已实现 | `/users/cert-status`（等级、信用、完成单、抢单额度） | — |
| CERT-02 | 提交技能认证 | 已实现 | `/certification/register` + 标签/地区 | — |
| CERT-03 | 升级等级 | 已实现 | `/users/upgrade-cert` | — |

### 2.12 服务卡

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| SC-01 | 我的服务卡列表 | 已实现 | `/service-cards/mine` | — |
| SC-02 | 创建 / 更新 | 部分实现 | `POST` / `PATCH /service-cards` | 编辑器固定 OFFLINE/ONSITE/AVAILABLE，不支持标签、最高价、交付方式与可用性选择 |
| SC-03 | 上架 / 下架 | 已实现 | publish / unpublish | — |
| SC-04 | 单卡详情 API | 未实现（UI） | `GET /service-cards/:id` | 编辑流直接用列表项 |
| SC-05 | 公开搜索服务卡 | 已实现 | 服务卡页「市场」分段 + `GET /service-cards/search` | E2：生产路由 200；当前可能为空样本 |
| SC-06 | 声明与经验事实 | 未实现 | ADR 定义 Claim/Evidence | macOS DTO/UI 没有声明高亮、完成样本、成功率或隐私化经验证据 |

### 2.13 福利

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| WEL-01 | 福利任务列表 | 已实现 | `/welfare/demands` | E2：生产 200，但当前空列表 |
| WEL-02 | 领取任务 | 需验证 | 客户端与生产现行 `POST /welfare/claim/:demandId` | 当前无任务样本做写路径 E4 |
| WEL-03 | 奖励记录 | 已实现 | `WelfareRewardDTO` + 福利中心「我的奖励」；`GET /welfare/rewards` | 当前无奖励样本 E4 |

### 2.14 个人资料与设置

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| SET-01 | 概览（头像/封面/信用/认证等级） | 已实现 | 读 `currentUser` | 无头像/封面上传 UI |
| SET-02 | 昵称 / 简介 | 已实现 | `PUT /users/profile` | — |
| SET-03 | 忙碌状态 | 已实现 | `/users/busy` | — |
| SET-04 | 我的标签 | 已实现 | GET/PUT `/users/tags` | — |
| SET-05 | 屏蔽标签 / 关键词 | 已实现 | `/users/blocklist` | 不是完整 `/pushes/preferences`；缺频率、接收开关、自动接收等偏好 |
| SET-06 | 法律文档 | 已实现 | 本地静态文案 | 非远程 CMS |
| SET-07 | API 地址 / 版本只读 | 已实现 | 设置页底部 | — |

### 2.15 帮助

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| H-01 | FAQ 帮助中心 | 部分实现 | 本地 `HelpFAQ`：发布、发现、订单支付、认证、沟通社区、平台特色 | 无远程内容；圈子说明已改为私人圈/邀请码口径 |

### 2.16 九木助手（Agent）

| ID | 能力 | 状态 | 关键实现 | 缺口 / 备注 |
|----|------|------|----------|-------------|
| A-01 | 会话列表 CRUD | 已实现 | `/agent/conversations` | — |
| A-02 | 流式对话（SSE） | 已实现 | `/agent/conversations/:id/stream`；`accessMode: "approval"`；客户端处理 `tool_pending` + `POST …/approve-tool` | 写工具须人机确认；只读/navigate 不弹批准卡 |
| A-03 | 快速 / 深度思考 | 已实现 | `thinkMode` + UserDefaults | — |
| A-04 | 思考过程展示 | 已实现 | streaming think + 历史 thinking | Markdown 渲染见 `NWMarkdownChatText` |
| A-05 | 非流式降级 | 已实现 | `sendMessageNonStream` | — |
| A-06 | 工具结果落地 / 页面跳转 | 已实现 | 只解析成功的 `tool_result(name=navigate_to)`；受控路由状态驱动主区、我的子页及需求/订单详情 | 不从回答文本猜跳转；后台管理、市场统计等 macOS 无产品面的路径会拒绝 |
| A-07 | Agent 任务独立页 | 未实现 | 云端交付路径已改回 `/agent` | 注释：任务管理页尚不存在 |

---

## 2.17 关键业务闭环

| 闭环 | 客户端链路 | 当前成熟度 | 主要断点 |
|------|------------|------------|----------|
| 发布需求 | 草稿校验 → 元数据 → multipart 发布 → 我的需求 | E1 + 路由 E2 + 领域 E3 + **API E4** | App UI E4 未自动化；创建响应资金字段已回传 |
| 两段式接单 | 请求接单 → 私信 → 发布者看申请人 → 接受 → 订单 | E1 + 路由 E2 + **API E4** | 沟通窗口缺真人双端 E4 |
| 卡池应标 | 应标 → 发布者查看报价 | E1 + 路由 E2 | 不成单（BR-003）；旧 accept-bid 已废弃 |
| 订单履约 | 预付 → 服务完成/部分完成 → 验收或争议 → 评价 | E1 + 路由 E2 + 策略 E3 + **API E4**（complete/confirm/dispute/cancel） | partial 与 review 步骤未进烟测批次；App UI E4 未自动化 |
| 消息协作 | 会话 → 历史消息 → Socket 增量 → 未读刷新 | E1/E2 + 通知深链 E3 | 缺 Socket E4 |
| Natural Loop | 推荐 → EARTH 执行 → HEAVEN 验证 → 运行详情/重试 | E1 + 公开目录 E2 | 运行写路径无 E4 |
| 私人圈 | 创建 → 邀请码 → 加入 → Hub → 管理 | E1 + 路由 E2 | 已隐藏公开圈入口；无认证 E4 |
| 福利 | 列表 → 领取 → 沟通/正式接单 → 完成/奖励 | E1 + 列表 E2 | 领取路径已修正；生产列表空，无样本 E4 |
| Agent | 会话 → SSE 回复 → 工具结果 → 受控导航 → 写工具批准 | E1 + 会话路由 E2 + 批准契约 E3 | App 手测 U8；写路径认证 E4 未做 |

## 2.18 客户端—文档—生产契约偏差

| ID | 严重度 | 偏差 | 业务影响 | 建议 |
|----|--------|------|----------|------|
| K-01 | 已修 | 生产需求详情返回 `deposit`，客户端原先未消费 | DTO/Mapper/详情已接入并展示 | **API E4** 已覆盖发布托管；App UI E4 未自动化 |
| K-02 | 已修 | 订单付款原先由 Mapper 固定推导 | 生产与 PaymentSheet 已接 `/pay-breakdown`；无分项时不允许确认付款 | **API E4** 已覆盖预付；App UI E4 未自动化 |
| K-03 | 已修 | 福利领取客户端路径错误 | 已改为生产现行 `/welfare/claim/:demandId` | 当前无任务样本 E4 |
| K-04 | 已修 | 争议原先只提交 `reason` 却声称有证据 | 已接图片上传、URL 与 `evidenceUrls`，服务端创建 Complaint | 待争议 E4 |
| K-05 | 已修 | `OrderDemandDTO.timeLimit` 类型漂移 | `FlexibleDateValue` 兼容 ISO 与历史 Int，并有 Fixture | — |
| K-06 | 已修 | `amountEstimate` 未消费 | DTO/Mapper 已兼容 `amountEstimate` / `expectedPrice` | — |
| K-07 | 已修 | `mediaUrls` 未消费 | DTO 与详情附件区已接 | — |
| K-08 | 已修 | 公开圈 UI 超出私人圈 Scope Lock | 已移除公开 Tab，仅暴露我的私人圈 | — |
| K-09 | P1 | 现行平台文档列 `/reject-acceptance`，生产与 macOS 使用 `/dispute` | 文档会误导下一次客户端/后端开发 | 以生产路由为准更新平台 API 对照，并记录兼容策略 |
| K-10 | 已修 | 卡片附件历史响应与 UI 原先缺失 | 已增加 CardAttachment DTO、服务端 include、领域气泡、发送入口与点击深链 | 群聊内卡片深链可后续统一 |
| K-11 | P2 | `/tags` 返回 1188 条但全部 `totalCompleted=0`，Agent 清单称 TagStats partial | UI/Agent 若直接展示会制造“零成交市场”假象 | 目录与统计分离；零覆盖时隐藏成交指标并披露样本 |
| K-12 | P2 | `/captcha` 返回空 siteKey | “接入验证码”不是单纯补 UI，当前云端配置也不完整 | 先确定验证码供应商和失败策略，再做登录接入 |
| K-13 | 已修 | 部分完成帮助文案与请求语义不一致 | 已改为 `newPrice`、剩余需求与服务端结果口径 | — |

---

## 3. 关键 API 差集与契约追踪

便于排期：既保留真正的“API 有、UI 无”差集，也追踪本轮刚接入但尚缺 E4 或完整契约的
关键接口，避免已接能力继续被旧清单误判为未实现。

| 领域 | API / 能力 | Service 入口 |
|------|------------|--------------|
| 认证登录 | `GET /captcha` | `CaptchaService`；生产 siteKey 为空，登录 UI 未接 |
| 需求 | `POST /demands/:id/extend-lifecycle` | 无 Service/UI |
| 需求 | `POST /demands/:id/extend-comm` | 已接 Service/Repository；消息页显示倒计时与发布者延期按钮 |
| 需求 | 应标转订单 | 现行契约没有 accept-bid；需收口 UI 语义，不应凭空补路由 |
| 用户 | `GET /users/snatch-status` | `UserService.snatchStatus` |
| 推送 | `GET/PUT /pushes/preferences` | 无 Service/UI；设置页 blocklist 不是完整推送偏好 |
| 市场 | `GET /tag-stats` | 无 Service/UI；`/tags` 的聚合字段当前不能替代 |
| 交易 | `/transactions/:demandId/breakdown`、`/transactions/history` | 无 Service/UI |
| 订单 | `GET /orders/:id/pay-breakdown` | 已接 Service 与 PaymentSheet；待测试钱包 E4 |
| 争议 | `POST /orders/uploads/evidence` + `evidenceUrls` | 已接图片/URL 举证；待争议样本 E4 |
| 消息 | 合并群聊全家桶 | 已接列表/创建/收发 UI；实时与成员资料仍弱 |
| 服务卡 | `GET /service-cards/search` | 已接「市场」分段浏览 |
| 福利 | `GET /welfare/rewards` | 已接 `WelfareRewardDTO` +「我的奖励」 |
| 福利 | 领取 / 完成 | 领取路径已修；完成与奖励选择流程仍缺写路径产品面 |
| 自然回 | `GET /loops/capabilities` | 已接自然回「系统能力」只读目录 |
| 自然回 | `GET /loops/runs?demandId=` | `LoopService.runs` |
| 钱包 | 在线充值 / 提现 | 无 Service；充值为 UI 占位 |
| 账号 | 头像/封面上传 | 无 UI |
| 账号 | 注册 | 已接 `RegisterView` + `/auth/send-code`/`/register`；正式 captcha/SMS 未配时须 `AUTH_SMS_FALLBACK` |

---

## 4. 云端 Agent 能力 vs macOS 暴露面

来源：`scripts/cloud-migrate/agent-router/` 的迁移包与测试。它能证明目标能力矩阵和
数据约束设计，但本仓库没有生产 `/opt/ninewood` 文件快照；除受保护 Agent 路由在线
外，不能仅凭迁移脚本断言每个工具已经在生产逐项验收。

| 云端能力 ID | 类型 | macOS 对应人工入口 | 客户端自动落地 |
|-------------|------|-------------------|----------------|
| `read_knowledge` | 机械只读 | 无独立知识库页 | 否（仅聊天文本） |
| `navigate_page` / `navigate_to` | 导航 | 侧栏、我的子页、需求/订单详情 | **是（受控白名单）**：只消费成功的结构化工具结果 |
| `search_demands` / `search_and_open_first` | 机械 / 复合链 | 发现、卡池 | 搜索结果仍只在对话中；若云端另发合法 `navigate_to`，可打开需求详情 |
| `get_demand_detail` | 机械只读 | 需求详情 | 否 |
| `list_my_demands` / `list_my_orders` / `list_my_applications` | 机械只读 | 我的需求 / 订单 / 应标 | 否 |
| `search_users` / `get_user_profile` | 机械只读 | 找人 / 资料 | 否 |
| `create_demand` / `update_demand` / `withdraw_demand` | 需确认写 | 发布 / 我的需求 | 云侧 `tool_pending` + macOS 批准 Sheet → `approve-tool` |
| `apply_for_demand` / `accept_applicant` / `reject_applicant` | 需确认写 | 详情 / 我的需求 | 同上 |
| `batch_withdraw_demands` / `schedule_demand_digest` | 写 / 调度 | 无批量 UI | 否 |
| `analyze_demand` / `analyze_providers` / `analyze_market` / `next_action_guidance` | 分析 | 无独立分析页 | 仅对话输出 |
| `get_market_stats` | 工具 | 无行情页 | 否 |

**数据真实性约束（助手不得误报）：** 见 `04-data-fidelity.yaml`

| 域 | 等级 | 含义 |
|----|------|------|
| `region_catalog` / `demand_region` | real | 能力矩阵允许作事实；但公开 `/regions` 本轮只返回 24 条，引用前仍要说明接口覆盖 |
| `tag_statistics` / `welfare_region` | partial | 可用但须声明覆盖有限 |
| `provider_region` | stub | **禁止**声称可靠同城服务者匹配 |

---

## 5. 资金与产品规则风险

详见 `docs/BUSINESS-RULE-GAPS.md`。

| 规则 | 状态 | 摘要 |
|------|------|------|
| BR-001 发布托管语义 | **已关（主路径）** | 产品为「全额最低报价托管」；详情与创建响应已回传 `deposit`/`payableNow`/`ruleVersion`（API E4 批次已验证托管扣款） |
| BR-002 订单金额推导 | **已关（付款路径）** | 付款强制 pay-breakdown；Mapper 不以 `minPrice` 作应付；列表缺字段显示「—」 |

**验收约束（`docs/QA-RUNBOOK.md`）：** 发布、预付、结算、争议、删除等写操作在生产账号须停在最终按钮前由用户确认；自动化与非破坏性回归见该文档。

---

## 6. 架构迁移完成度（影响可测性，非业务有无）

摘自 `docs/ARCHITECTURE-MODERNIZATION.md`，便于区分「业务已上线」与「工程边界已现代化」：

| 工作包 | 状态 |
|--------|------|
| 发布 Domain + Repository | 已完成 |
| 发现 / 订单 / 消息 Feature Model + Repository | 已完成 |
| 订单动作策略可测 | 已完成 |
| 详情页 Feature Model | 已完成 |
| DTO 首批分域 + Fixture | 已覆盖需求详情资金/附件、订单时间、付款分项、消息上下文/卡片、福利奖励与 Agent 导航 |
| 资金机读契约 | 已完成主路径：`buildMoneySummary` 覆盖发布创建与订单列表/详情；付款强制 pay-breakdown；Mapper 不以 `minPrice` 作应付 |
| 圈子 / 钱包 / 认证 / 服务卡 / 福利 / Agent 等 Feature Model 化 | 未完成（多为 View 直连 Service） |
| 登录→自然回非破坏性 UI 回归 | 待测试环境 |

### 自动化保护现状

根 Swift Package 当前声明 **30 项 XCTest，本机已全部通过**（需指向完整 Xcode：
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`；若 `xcode-select` 仍指向
Command Line Tools，会误报找不到 `XCTest`）。亦可用 `scripts/test-with-xcode.sh`。

| 测试组 | 数量 | 已覆盖 | 未覆盖 |
|--------|------|--------|--------|
| `DemandDraftTests` | 6 | 必填、金额、地区、人数、重置 | multipart 字段、真实托管扣款 |
| `OrderActionPolicyTests` | 8 | 角色/阶段/预付/取消/争议门控、`OrderPaymentGate` | 服务端鉴权、重复评价 |
| `APIContractDecodingTests` | 16 | Decimal、资金摘要、付款分项、争议编码、沟通/卡片/福利/Agent 导航与 `tool_pending`、通知深链 | 钱包/Loop/Circle 生产 Fixture |

仍缺的高价值自动化：

1. `APIClient` 的 401 清会话、429 冷却、Request ID、裸 JSON/信封错误；
2. 使用脱敏生产响应固化 Demand/Order/Message/Loop Fixture；
3. Feature Model 的选中项保持、失败重试、实时消息去重；
4. Socket 实时 E4；Mac App UI 交易手测清单（见 QA-RUNBOOK）；
5. CI 正式接入 `scripts/test-with-xcode.sh`。

---

## 7. 总览矩阵

| 业务域 | 状态 | 最高证据 | 一句话 |
|--------|------|----------|--------|
| 登录 / 会话 | 已实现 | E2 | Token/401/健康检查完整；注册已接；captcha/SMS 正式供应商未配（fallback） |
| 发现撮合 | 已实现 | E2 | 公开列表与详情在线；金额、附件、生命周期字段已接 |
| 发布 | 已实现 | **API E4** | 表单/校验/幂等 + 托管扣款烟测通过；App UI E4 未自动化 |
| 卡池 / 死池 | 部分实现 | E2 | 活跃池有样本；死池空；snatch 非成单主链 |
| 我的需求 | 部分实现 | E2 | applicant 主链已接；应标只读不成单 |
| 订单 | 已实现 | **API E4** + E3 | 付款门控、争议证据、动作策略；App UI E4 未自动化 |
| 钱包 | 部分实现 | E2 | 查账在线；充值占位、无提现 |
| 消息 | 部分实现 | E2 | 1:1、卡片深链、通知已读、沟通窗口、群聊 UI 已接；无 Socket E4 |
| 自然回 | 已实现 | E2 | EARTH offering 与 HEAVEN 能力在线；客户端已有只读能力目录 |
| 圈子 | 已实现 | E1 | 私人圈创建、邀请码加入、Hub 与管理入口完整；公开入口已按 Scope Lock 隐藏 |
| 找人 / 关注 / 收藏 | 已实现 | E2 | 路由与 UI 已接；没有关系操作 E4 |
| 认证 | 已实现 | E2 | 状态、注册、升级 UI 已接；无认证账号 E4 |
| 服务卡 | 部分实现 | E2 | 自管与「市场」公开搜索已接；生产当前无公开样本，编辑字段仍不完整 |
| 福利 | 需验证 | E2 | 列表在线、领取路径已修、奖励记录 UI 已接；无样本 E4，完成写路径仍缺 |
| 通知 | 部分实现 | E2 + E3 | 分页、已读、订单/需求/path 深链已接；生产通知多为 SYSTEM+orderId |
| 设置 / 帮助 / 法律 | 部分实现 | E1 | 设置可写；帮助/法律为本地静态；圈子帮助文案已对齐私人圈 Scope Lock |
| 九木助手 | 部分实现 | E2 | 会话、SSE、受控导航与写工具批准卡已接；缺认证写路径 E4 |

---

## 8. 建议补齐优先级

按「业务损害 × 契约确定性 × 修复前置关系」排序：

1. ~~**P0：补交易写路径 E4**~~ — **已完成（2026-07-17）**：`e4-trade-loop-smoke.sh` 覆盖发布托管、
   pay-breakdown/prepay、complete/confirm、dispute、cancel；证据见 `QA-RUNBOOK.md`。
2. ~~**P1：完善资金摘要契约**~~ — **已完成**：创建响应与订单列表/详情统一 `deposit/escrow/serviceFee/remainingPay/payableNow/ruleVersion`；客户端去掉付款路径 `minPrice` 回退。
3. ~~**P1：收口应标/抢单语义**~~ — **已完成**：主链锁定 applicant 两段式；UI/帮助标明应标/抢单不成单；不复活 accept-bid。
4. ~~**P1：扩展自动测试与 CI 固定 Xcode**~~ — **已推进**：资金 DTO / 争议编码 / PaymentGate / 动作门控矩阵；`scripts/test-with-xcode.sh` 固定 `DEVELOPER_DIR`。
5. **P1：补消息实时 E4** — 验证 Socket 重连/去重、群聊实时消息和卡片发送（通知多对象深链本轮已接）。
6. **P2：清理残余差集** — 补完整推送偏好、服务卡编辑字段和按需求查询 Natural Loop runs。
7. **产品策略项：充值/提现、头像上传、hCaptcha/短信正式供应商** — 开发期模拟点数与注册 fallback 仍可用；
   正式供应商配置后关闭 fallback。

---

## 9. 维护说明

- 本清单描述的是 **macOS 客户端业务暴露面**，不是云端全部能力目录。  
- 事实优先级：生产非破坏性响应 > 现行后端 ADR/开发主线 > macOS 可执行代码 >
  迁移脚本/注释 > UI 文案。发生冲突时必须保留冲突记录，不能静默选一个口径。
- 变更业务入口或写操作时，请同步更新本文件对应 ID、证据等级，并视需要更新
  `QA-RUNBOOK.md` / `BUSINESS-RULE-GAPS.md`。  
- 涉及资金写路径的变更，除单测外必须按 QA 手册在测试账号完成人工确认。
- 生产探测只允许无 Token GET，或使用假 ID/空凭证确认路由存在且不会越过 401；不得
  为更新清单而触发真实发布、领取、支付、结算、争议或删除。
- `scripts/cloud-migrate/*` 是部署意图与迁移证据，不是生产文件快照。宣称 Agent 工具
  已上线前，应补生产能力版本端点或部署清单。

### 主要证据索引

| 主题 | 权威材料 |
|------|----------|
| macOS 客户端定位与契约 | `ninewood-docs/MACOS-CLIENT.md` |
| 平台现行业务规则与真实路由表 | `ninewood-docs/DEVELOPMENT-GUIDE.md` |
| 需求卡 / 服务卡 / 卡片附件 | `ninewood-docs/specs/DEMAND-SERVICE-CARD-ADR.md` |
| Natural Loop V2 | `ninewood-docs/specs/NATURAL-LOOP-V2-ADR.md` |
| 客户端架构 | `docs/MACOS-ARCHITECTURE.md` |
| 资金规则差异 | `docs/BUSINESS-RULE-GAPS.md` |
| 风险动作验收 | `docs/QA-RUNBOOK.md` |
| 客户端领域与契约测试 | `Package.swift`、`Tests/NinewoodPublishDomainTests/` |
