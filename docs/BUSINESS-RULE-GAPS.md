# 客户端与产品规则差异

## BR-001：发布需求时的资金语义

### 现有证据

- `ninewood-docs/DEVELOPMENT-GUIDE.md` 已明确：现行产品决策为每条需求全额托管最低
  报价，“多单 1%”模型已废弃。
- 当前 macOS 发布文案与这一产品口径一致。
- 生产需求详情已返回 `deposit`；macOS `DemandDetailDTO` 已接入并在详情展示。
- `GET /api/orders/:id/pay-breakdown` 已在生产提供付款前服务端分项；PaymentSheet 以该响应为准。
- **2026-07-17：** 创建需求成功响应已补齐 `currency` / `ruleVersion` /
  `depositRequired` / `escrowRequired` / `serviceFeeRate` / `payableNow` 等机器可读字段
  （`buildMoneySummary`）；E4 烟测可见。

### 风险

列表/订单摘要在缺少服务端资金字段时不得用 `minPrice` 冒充托管或应付。

### 当前处理

- 不改变生产请求字段；
- 将发布数据规范化集中在 `DemandPublishCommand`；
- 将订单动作门控集中在 `OrderActionPolicy`；
- 按现行文档保留“全额最低报价托管”的产品提示；
- 付款页加载 `pay-breakdown`，展示 `payableNow` / `escrowHeld` / `ruleVersion`；无预览禁止确认；
- 所有真实发布、预付、结算仍需用户在最终动作前确认。

### 状态

**已关闭（客户端 + 生产契约）**。残留产品策略项：真实充值/提现。

## BR-002：订单映射中的金额

订单列表/详情已返回 `escrowAmount` / `serviceFee` / `remainingPay` / `ruleVersion` 等字段；
`OrderMapper` 优先消费这些字段，缺失时展示「—」，**不再**用 `minPrice` 回退驱动付款。
`pay-breakdown` 仍是预付确认权威来源。

### 状态

**已关闭。**

## BR-003：应标 / 抢单与 applicant 主链

### 产品口径（已锁定）

- **唯一成单主链：** `request` → `accept/:applicantId` → 订单。
- **应标 (`/bid`)、抢单 (`/snatch`)**：保留为意向/遗留入口；**不实现 accept-bid**。
- 帮助、需求详情、我的需求 UI 已标明应标不可直接成单。

### 状态

**文档与 UI 已收口**；死池 snatch 生产语义若再变更，仅更新文案，不复活 accept-bid。
