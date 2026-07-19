# 缺陷报告验收标准（Acceptance Criteria）

> **依据：** [docs/GAP-AUDIT-REPORT.md](GAP-AUDIT-REPORT.md)  
> **制定日：** 2026-07-18  
> **用法：** 每条 AC 必须可判定 pass/fail；修复任务完成时在「验收记录」勾选并附证据链接。

证据等级沿用 E1–E4。**禁止**用更低证据冒充更高完成态。

---

## AC-0 元数据与口径（P0）

| ID | 验收标准 | 判定 |
|----|----------|------|
| AC-0.1 | `BUSINESS-INVENTORY.md` 文首不再声称「写路径仍无 E4」；明确区分 **API E4** 与 **App UI E4** | 全文检索无冲突表述 |
| AC-0.2 | §2.17 / §2.18 / §3 / §6 / §8 与当前现实一致：注册已实现、测试数以 `swift test` 实采为准、资金 mapper 无 minPrice 付款回退、BR-001/002 已关 | 人工对照 GAP 报告 §3.9 |
| AC-0.3 | `GAP-AUDIT-REPORT.md` 与本 AC 互相引用；本文件列出本轮修复范围 | 文件存在且交叉链接有效 |

**本轮必须 pass。**

---

## AC-1 注册反滥用硬化（P0）

> 在尚未配置正式 hCaptcha/SMS 密钥前，不允许「看起来像正式短信」的静默回传；必须可审计、可关闭。

| ID | 验收标准 | 判定 |
|----|----------|------|
| AC-1.1 | `GET /captcha` 明确返回 `mode`：`hcaptcha` \| `bypass`；bypass 仅当 siteKey/secret 未配置 | curl 断言 |
| AC-1.2 | SMS 未配置时，发码响应必须带 `delivery: "fallback"`；**不得**在未标注时回传 code | curl 断言 |
| AC-1.3 | 生产 `.env` 增加显式开关说明：`AUTH_SMS_FALLBACK=1`（或缺省行为文档化）；关闭后未配 SMS 应返回 503 | 服务端代码 + 文档 |
| AC-1.4 | macOS 注册页：fallback 时用醒目提示「当前为开发通道，验证码由服务端回传」；正式 SMS 时不展示明文 code 条 | UI 代码审查 |
| AC-1.5 | 登录页展示后端连通与 captcha 模式（bypass 时二次提示）可选但推荐 | UI 或帮助文案 |

**本轮目标：** AC-1.1–1.4 pass。正式供应商密钥配置属产品策略，记为 AC-1.FUTURE。

| ID | 未来项 | 判定 |
|----|--------|------|
| AC-1.FUTURE | 配置真实 HCAPTCHA_* 与 TENCENT_SMS_* 后，`mode=hcaptcha` 且发码不再回传 code | 运维配置后 E2 |

---

## AC-2 Agent 写工具批准卡（P1）

| ID | 验收标准 | 判定 |
|----|----------|------|
| AC-2.1 | 流式对话在云侧要求 approval 的写工具时，macOS 弹出确认 Sheet（工具名、摘要、允许/拒绝） | E1 + 手工或模拟事件 |
| AC-2.2 | 用户点「允许」后，客户端以约定方式续跑（重发确认消息或调用 approve API，以生产契约为准） | 对接现有服务端协议 |
| AC-2.3 | 用户点「拒绝」后，对话中留下拒绝说明，不执行写操作 | 同上 |
| AC-2.4 | 只读工具与 `navigate_to` 成功结果不弹出批准卡 | 回归 |

若生产暂无独立 approve 端点，则采用「用户确认后以明确指令续发」的 MVP，并在 AC 记录中写明协议版本。

---

## AC-3 通知统一深链（P1）

| ID | 验收标准 | 判定 |
|----|----------|------|
| AC-3.1 | 通知模型除 `orderId` 外识别 `demandId` / `path` / `type`（兼容现有字段） | DTO + 单测 |
| AC-3.2 | 点击通知：订单→订单详情；需求→需求详情；带 `/…` path→`AppNavigation`；无法识别→明确 toast，不静默 | UI + 导航 |
| AC-3.3 | 清单 MSG 相关缺口从「仅 orderId」更新为「多对象深链已接」 | inventory 更新 |

---

## AC-4 交易证据分层（P1，文档+轻量）

| ID | 验收标准 | 判定 |
|----|----------|------|
| AC-4.1 | QA-RUNBOOK 增加「App UI 手测清单」与 API 烟测并列，标明当前最高证据=API E4 | 文档 |
| AC-4.2 | E4 脚本补评价 A8 或显式标注 A8 未跑 | 脚本或 QA 备注 |

---

## AC-5 本轮明确不做（避免范围膨胀）

- 真实充值/提现支付通道  
- 正式 hCaptcha/SMS 采购与密钥填入（无密钥则无法 AC-1.FUTURE）  
- 服务卡/福利生产样本播种（需运营数据）  
- Socket 全链路压测 E4  
- Sentry 商业账号开通（可加「未配置」健康提示，不开通付费）  

---

## 本轮修复顺序

1. AC-0 文档纠偏  
2. AC-1 反滥用硬化（服务端+客户端）  
3. AC-3 通知深链  
4. AC-2 Agent 批准卡 MVP  
5. AC-4 QA 分层  
6. `swift test` + `xcodebuild` 绿；回写下方验收记录  

---

## 验收记录

| AC | 结果 | 日期 | 证据 |
|----|------|------|------|
| AC-0.1–0.3 | **pass** | 2026-07-19 | inventory 文首区分 API/App UI E4；与 `GAP-AUDIT-REPORT` 交叉链接；测试数与自动化实采同步 |
| AC-1.1–1.4 | **pass** | 2026-07-18 | `GET /captcha`→`mode=bypass`；`delivery=fallback`+code；`AUTH_SMS_FALLBACK=0`→503；生产已设 `=1`；RegisterView 开发通道横幅 |
| AC-2.1–2.4 | **pass**（E1+契约） | 2026-07-18 | `AgentPendingToolEvent` + Sheet + `POST …/approve-tool`；只读/`navigate_to`/`tool_result` 不弹卡；单测 `testAgentPendingToolEventContract` |
| AC-3.1–3.3 | **pass** | 2026-07-18 | `NotificationDeepLink`（order/demand/path/none）；NotificationsView 跳转；`testNotificationDeepLinkResolvesOrderDemandAndPath`；inventory 通知口径已更新 |
| AC-4.1–4.2 | **pass** | 2026-07-18 | QA-RUNBOOK 增加 App UI 手测清单 U1–U8；显式标注 A8 评价未进烟测脚本 |
