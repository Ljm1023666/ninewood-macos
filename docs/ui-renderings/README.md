# 九木 macOS 页面渲染图

> 基准：2026-07-18  
> 画布：1440 × 1024  
> 用途：产品视觉方向、SwiftUI 页面实现与视觉验收参考

## 统一视觉语言

- 原生 macOS 浅色界面，使用侧栏、列表—详情分栏、工具栏与原生 Sheet。
- 品牌主色为 `#2FBBE0`，成功色为 `#42CFA5`，`#D62828` 仅用于紧急或破坏性动作。
- 以 8pt 间距体系、细分隔线和克制圆角建立层级，避免卡片套卡片和装饰性仪表盘。
- 业务主线围绕需求、可靠回应、沟通、履约、托管与证据，不引入电商或社交媒体语义。

## 页面索引

| 编号 | 页面 | 文件 |
|------|------|------|
| 01 | 登录 | `01-login.png` |
| 02 | 注册 | `02-register.png` |
| 03 | 发现 / 需求详情 | `03-discover.png` |
| 04 | 卡池 / 应标 | `04-card-pool.png` |
| 05 | 发布需求 | `05-publish.png` |
| 06 | 私人圈 / 圈子详情 | `06-circles.png` |
| 07 | 自然回 / 运行详情 | `07-natural-loop.png` |
| 08 | 找人 / 服务者资料 | `08-find-people.png` |
| 09 | 消息 / 私聊 | `09-messages-direct.png` |
| 10 | 认证中心 | `10-certification.png` |
| 11 | 消息 / 群聊 | `11-messages-group.png` |
| 12 | 我的 / 个人中心 | `12-profile.png` |
| 13 | 订单 / 订单详情 | `13-orders.png` |
| 14 | 我的需求 / 申请人 | `14-my-demands.png` |
| 15 | 钱包与托管 / 流水详情 | `15-wallet.png` |
| 16 | 服务卡 / 公开预览 | `16-service-cards.png` |
| 17 | 通知 / 业务对象跳转 | `17-notifications.png` |
| 18 | 福利中心 / 任务详情 | `18-welfare.png` |
| 19 | 九木助手 / 工具结果 | `19-agent.png` |
| 20 | 设置 / 个人资料 | `20-settings.png` |
| 21 | 帮助中心 / 文档详情 | `21-help.png` |
| 22 | 我的应标 / 应标详情 | `22-my-bids.png` |
| 23 | 关注与粉丝 / 用户资料 | `23-follows.png` |
| 24 | 收藏 / 需求详情 | `24-favorites.png` |
| 25 | 订单争议 / 证据提交 | `25-dispute-sheet.png` |
| 26 | 服务费预付 / 服务端金额预览 | `26-payment-sheet.png` |

## 使用说明

这些图片是统一视觉方向的高保真概念稿，不是对现有 SwiftUI 截图的逐像素复制。实现时应以
现行业务契约和 `docs/BUSINESS-INVENTORY.md` 为准；渲染图中的示例姓名、时间、金额与内容
仅用于表达信息层级。
