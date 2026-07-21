# 九木项目 · 产品理念对照审计报告

> **审计日：** 2026-07-21  
> **依据：** [docs/PRODUCT-PRINCIPLES.md](PRODUCT-PRINCIPLES.md)  
> **范围：** macOS 客户端仓库 `ninewood-macos`（Views / API / Domain / Store）  
> **方法：** 五路并行代码审查（沉迷式设计、推送自定义、付费曝光/中介化、会员分层、收费透明度），全部基于实际 Grep/Read 结果，非推测  
> **结论口吻：** 只记录代码里能证明的事实；未发现的一律写「未发现」，不臆测服务端/未开源部分  
> **验收标准：** 本报告缺陷落地判定见 [PRINCIPLES-ACCEPTANCE-CRITERIA.md](PRINCIPLES-ACCEPTANCE-CRITERIA.md)

---

## 0. 一句话总判

代码底子是干净的：**没有**无限流、时长/签到埋点、付费置顶、付费解锁联系、会员分层残留、自动播放。真正偏离原则的问题集中在**两处**——**收费时点**（服务费在验收成功前就预扣）和**推送默认值**（默认开、粒度太粗）；另有一处**紧迫感 UI**（倒计时式「剩余可见」）值得警惕，因为它和短视频平台常用的心理钩子是同一机制，即便出发点是业务时效性。

---

## 1. 审计矩阵总表

| 域 | 对照原则 | 结论 | 最高严重项 |
|----|----------|------|------------|
| 沉迷式设计 / 信息流 | 原则 §2.1 反沉迷 | **基本干净** | 中（倒计时紧迫感 UI） |
| 推送与通知自定义 | 原则 §2.2 推送自定义 | **有缺口** | 中（默认开 + 粒度粗） |
| 付费曝光 / 中介化 | 原则 §2.3 去中介化 | **未发现问题** | 低（演示数据硬置顶） |
| 会员分层 / 差别化服务 | 原则 §2.4 无差别服务 | **未发现问题** | — |
| 收费透明度 / 结果导向 | 原则 §2.5 单一入口收费 | **有明确违反** | **高**（预付即扣费） |

---

## 2. 分域明细

### 2.1 沉迷式设计与信息流（PR-GAP-1x）

**结论：未发现典型「无限算法信息流 + 时长埋点 + 签到钩子 + 自动播」组合。**

| ID | 差距点 | 位置 | 严重度 |
|----|--------|------|--------|
| PR-GAP-11 | 「剩余可见」红色倒计时制造紧迫感 | `Views/Discover/DiscoverView.swift:269-274`、`Views/Discover/DemandDetailView.swift:282-287` | 中 |
| PR-GAP-12 | 卡池按「即将截止」排序 + 倒计时展示 | `Views/CardPool/CardPoolView.swift:232,290,440-441` | 中 |
| PR-GAP-13 | 截止前 1 小时标记 `.urgent` 态，作为紧迫感数据源 | `API/Services/DemandService.swift:460-464` | 低 |
| PR-GAP-14 | Loop 状态轮询（15s 间隔）属进度同步，非内容推荐流，暂不算问题 | `Views/Loop/LoopMineView.swift:164-173`、`NaturalLoopWorkspaceView.swift:1559-1578` | 低（信息，非缺陷） |

**已排除（明确未发现，不需要处理）：**
- 无限滚动 / 滚动到底自动加载
- 「猜你喜欢」个性化推荐排序
- 用户时长 / 签到 / 连续登录埋点字段
- 主动引诱式 Badge（现有未读数均反映真实状态）
- 自动播放视频/音频

### 2.2 推送与通知自定义（PR-GAP-2x）

**结论：客户端无系统级 APNs/本地推送实现；现有能力是站内通知 + 「匹配需求推送」偏好设置，默认开且粒度粗。**

| ID | 差距点 | 位置 | 严重度 |
|----|--------|------|--------|
| PR-GAP-21 | `receivePushes` 默认 `true`，API 缺省时客户端仍强制默认开 | `Views/Profile/AccountExtrasViews.swift:1810-1811, 2243-2244` | 中 |
| PR-GAP-22 | 站内通知（订单/需求/系统/福利）无按类别独立开关，仅「匹配需求推送」一类有总开关+频率 | `Views/Profile/AccountExtrasViews.swift:2032-2064`、`NotificationsView` | 中 |
| PR-GAP-23 | 服务端 DTO 已有 `excludeRegions` 字段，设置页未暴露 | `API/ParityDTOs.swift:133-138` | 低 |
| PR-GAP-24 | 认证通过后「可接收带标签推送」文案，偏好绑定认证动作而非显式订阅流程（是否服务端自动订阅需云端确认） | `Views/Profile/CertCenterView.swift:52` | 低 |

**已排除：**
- 运营/营销/活动提醒的客户端发送逻辑 — 未发现
- Keychain/Session 中的唤回/活跃度触发字段 — 未发现
- 独立「通知类别偏好」整页（现状是嵌在设置页里的一小块）

### 2.3 付费曝光与中介化（PR-GAP-3x）

**结论：未发现「用钱买曝光/排名」或「付费解锁联系」的产品设计。**

| ID | 差距点 | 位置 | 严重度 |
|----|--------|------|--------|
| PR-GAP-31 | 找人页种子账号 UUID 硬编码置顶（演示数据，非付费加权） | `Views/People/FindPeopleView.swift:290-306` | 低（上线前需清理） |
| PR-GAP-32 | 圈子「置顶公告」为管理免费功能，非付费，仅记录以防未来误加商业化 | `Views/Circles/CirclesView.swift:1434`、`CircleLiveDetailView.swift:435` | 低（信息） |

**已排除：** 需求/服务卡排序（时间/距离/预算/截止等客观维度，无付费加权字段）、曝光包/流量包概念、付费解锁联系人、发布工作台付费推广引导 — 均未发现。

### 2.4 会员分层与差别化服务（PR-GAP-4x）

**结论：未发现会员制 / `isPremium` 类功能分支残留。**

未发现 `isPremium` / `isVip` / 会员分级 / StoreKit 内购 / 「仅会员可见」等任何形式的差别化服务代码。关键词命中均为非目标语义（圈子成员 `isMember`、技能认证升级 `upgrade-cert`、法律文案「权益」）。

**相邻但非会员制、供长期关注：**

| ID | 事项 | 位置 | 判断 |
|----|------|------|------|
| PR-GAP-41 | 技能认证门槛：「仅认证服务者可申请」开关 | `Views/Publish/CreateDemandView.swift:380-383` | 信任准入，非付费分层；原则文档未禁止认证门槛，但需在未来讨论中明确边界 |

### 2.5 收费透明度与结果导向（PR-GAP-5x）—— 本轮最高优先级

**结论：客户端未见广告/内购/会员费，佣金/手续费是唯一收入入口，这点符合原则；但收费时点与展示透明度不符合「没帮到不收费」「完全公开」。**

| ID | 差距点 | 位置 | 严重度 |
|----|--------|------|--------|
| **PR-GAP-51** | ~~服务费在「进行中」阶段就预扣~~ → **已定案落地（2026-07-21）**：预付改为 `WalletServiceFeeHold` 托管；验收 `consume` 后才计入平台收入；取消/争议退款 `release` 全额退回 | order/wallet/admin 服务 | **已关闭** |
| **PR-GAP-52** | 手续费比例硬编码「5%」，不读服务端真实费率；服务端字段缺失时客户端自行回落默认 5% | `Views/Orders/OrdersViews.swift:767, 1017, 1031`、`Views/Wallet/WalletView.swift:88` | **高** |
| PR-GAP-53 | 钱包流水/结算详情只有金额，没有「基数 × 费率 = 手续费」的计算过程展示；DTO 缺 `feeRate`/`baseAmount` 字段 | `Views/Wallet/WalletView.swift:308-368`、`API/APIResponse.swift:116-125` | 中 |
| PR-GAP-54 | 《服务协议》《服务费规则》仅文字染色，无可点击链接，规则不可核对 | `Views/Orders/PaymentPrepayDesignView.swift:303` | 中 |
| PR-GAP-55 | 帮助中心「托管费用如何计算」FAQ 为空壳，无比例/公式说明 | `Views/Help/HelpView.swift:259` | 中 |
| PR-GAP-56 | 设计预览 fixture 用 10% 费率，与线上文案 5% 不一致，可能误导 QA | `Views/Orders/OrdersViews.swift:263,594` | 低 |

**已排除：** 广告 SDK、内购/StoreKit、会员费等第二收费入口 — 未发现，`Package.swift` 无相关依赖。

---

## 3. 风险叙事（给决策者）

1. **最直接违反已写下承诺的：** PR-GAP-51。产品原则明确写「没有帮到你，不会产生任何费用」，但当前实现里费用在服务尚未验收完成前就已经扣了。这不是体验细节，是**对外承诺与代码行为不一致**。
2. **最容易被用户发现、影响信任的：** PR-GAP-52/53。硬编码费率意味着一旦服务端调整定价策略（哪怕是降价），客户端界面还在说谎；钱包看不到计算过程，意味着"完全公开"目前只停留在文档里。
3. **最像短视频套路、需要警惕但不紧急的：** PR-GAP-11/12。倒计时+红色强调的组合本身是中性技术，用在这里制造的是"错过就没了"的焦虑，值得在下一轮视觉设计时替换掉。
4. **不紧急，但顺手就该改的：** 推送默认值（PR-GAP-21/22）、找人页硬编码占位数据（PR-GAP-31）上线前必须清理。

---

## 4. 建议修复顺序（不扩 scope）

1. **PR-GAP-51 收费时点** — 涉及资金逻辑，需服务端配合，优先讨论方案（验收后收 vs 预付托管+自动全额退）
2. **PR-GAP-52 硬编码费率** — 纯客户端改动，读服务端真实字段，无字段就不显示具体数字
3. **PR-GAP-11/12 紧迫感 UI** — 纯客户端视觉改动，去掉倒计时式红色强调
4. **PR-GAP-21/22 推送默认值与粒度** — 客户端改默认值 + 补分类别开关，需要服务端字段配合细粒度部分
5. **PR-GAP-53/54/55 收费展示完整性** — 需服务端补 DTO 字段（feeRate/baseAmount），客户端配合展示
6. **PR-GAP-31 演示数据清理** — 上线前必须做，优先级低但阻断上线

---

## 5. 关键代码锚点

| 主题 | 路径 |
|------|------|
| 收费时点/状态机 | `ninewood-macos/Domain/Orders/OrderActionPolicy.swift` |
| 预付/结算展示 | `ninewood-macos/Views/Orders/OrdersViews.swift`、`PaymentPrepayDesignView.swift` |
| 钱包流水 | `ninewood-macos/Views/Wallet/WalletView.swift`、`API/Services/WalletService.swift` |
| 推送偏好 | `ninewood-macos/Views/Profile/AccountExtrasViews.swift` |
| 紧迫感 UI | `ninewood-macos/Views/Discover/DiscoverView.swift`、`Views/CardPool/CardPoolView.swift` |
| 产品原则依据 | `docs/PRODUCT-PRINCIPLES.md` |

---

*本报告描述差距与证据。落地修复与 pass/fail 判定见 [PRINCIPLES-ACCEPTANCE-CRITERIA.md](PRINCIPLES-ACCEPTANCE-CRITERIA.md)。*
