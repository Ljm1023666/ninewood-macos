# 桌面前端 → 后端操作级对照表

> **用途：** 后端按「每一个组件 / 按钮 / 操作」对齐 macOS 客户端。  
> **基准：** 2026-07-18 · Views + `API/Services/*`  
> **更新：** 2026-07-19 00:10 — P1/P2 缺口全量接通（服务端新路由 + macOS 接线）  
> **生产：** `https://tothetomorrow.com/api` · 代码 `/opt/ninewood/server` · 主机 `8.217.208.203`  
> **状态列说明：**
> - **已接** = 生产壳层（`MainShellView()` 无 `designPreview*`）会打 API  
> - **有 API 未接** = Service/生产有路由，但当前**活跃 UI**未调用（含死代码路径）  
> - **仅本地** = 纯前端状态，不需要后端  
> - **缺失** = 产品有交互，后端尚无契约或明确不做  
> - **[预览]** = 仅 `NINEWOOD_DESIGN_PREVIEW` / `*-design-preview` / 显式注入 fixtures 时；属预期 No-op  

**2026-07-19 桌面后端接通进度（已复验）：**  
原 P0/P1 主链保持；本轮补齐：发现 keyword/附近、找人筛芯片、推送排除词、头像/封面 multipart、分享/举报、钱包流水详情+**模拟充提**、帮助深链、**服务卡收藏**、**需求草稿**、**撤回应标**、**忘记密码**、群聊 mute/leave/加人/共享文件、认证证明上传。  
侧栏仍为嵌套 IA；设计预览路径仍为 fixtures + No-op。  
充值/提现为**模拟点数**（非真实支付）。

---

## 图例

| 标记 | 含义 |
|------|------|
| `→` | 用户操作触发的后端调用 |
| `(auto)` | 进入页/选中行自动加载 |
| `[预览]` | 设计稿路径当前可能未真正打 API |

---

# 0. 壳层 · MainShellView

> 主侧栏对齐发现渲染图三组；履约/账户子页嵌在 **我的**（`ProfileView` 二级导航），**不平铺**。争议 Sheet / 预付 Sheet 仅从订单详情打开。

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| S01 | 侧栏·主区 | 发现 / 卡池 / 发布 / 圈子 | 点击 | 切换 `selection` | 仅本地路由 | 仅本地 |
| S02 | 侧栏·协作 | 自然回 / 找人 / 消息 | 点击 | 同上 | 仅本地 | 仅本地 |
| S03 | 侧栏·账户 | 认证 / 帮助 / 我的 | 点击 | 同上；「我的」进二级导航 | 仅本地 | 仅本地 |
| S04 | 我的·二级 | 订单 / 需求 / 应标 / 钱包 / 服务卡 / 通知 / 福利 / 助手 / 设置 / 关注 / 收藏 / … | 点击 | `ProfileNav` 切页 | 各子页自有 API | 已接（见各章） |
| S05 | 消息项 | 未读角标 | (auto) 刷新 | 显示数字 | `GET /messages/unread-count` | 已接 |
| S06 | 侧栏底 | 退出登录 | 点击 | 清 Token | `POST /auth/logout` | 已接 |
| S07 | 深链 Sheet | 需求/订单详情加载 | 打开 path | 拉详情 | `GET /demands/:id` / `GET /orders/:id` | 已接 |
| S08 | Sheet | 关闭 | 点击 | dismiss | 仅本地 | 仅本地 |
| S09 | — | 争议 / 预付 | — | **非侧栏项**；订单动作打开 Sheet | 见 #25 / #26 | 已接入口在订单详情 |

---

# 01 · 登录 LoginView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| L01 | 表单 | 手机号 TextField | 输入 | 绑定 phone | 仅本地 | 仅本地 |
| L02 | 表单 | 密码字段 | 输入 | 绑定 password | 仅本地 | 仅本地 |
| L03 | 表单 | 显示/隐藏密码 | 点击 | 切换明文 | 仅本地 | 仅本地 |
| L04 | 表单 | 忘记密码？ | 点击 | Sheet：手机+验证码+新密码 | `POST /auth/send-reset-code` · `POST /auth/reset-password` | 已接 |
| L05 | 表单 | 登录 | 点击 | `session.login` | `POST /auth/login` `{phone,password}` → token + user | 已接 |
| L06 | 表单 | 注册 | 点击 | 切到注册页 | 仅本地 | 仅本地 |
| L07 | 连接条 | 重试 | 点击 | 探测后端 | 健康检查 / 可达性 | 已接（非 Auth） |
| L08 | Alert | 确定 / 知道了 | 点击 | 关闭 | 仅本地 | 仅本地 |
| L09 | 文案 | 《用户协议》《隐私政策》 | — | 当前不可点 | 可选：静态或 CMS | **缺失交互** |
| L10 | [预览] | 登录/忘记密码 | 点击 | No-op | 同 L05/L04 | 预览 |

**后端字段要求：** 登录成功返回可解码的 user（含 nickname、creditScore、certificationLevel、avatar 等桌面概览字段）。

---

# 02 · 注册 RegisterView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| R01 | 顶栏 | ← 返回登录 | 点击 | 回登录 | 仅本地 | 仅本地 |
| R02 | 表单 | 手机号 | 输入 | 绑定 | 仅本地 | 仅本地 |
| R03 | 表单 | +86 区号 UI | — | 不可选 | 多国家码 | **缺失** |
| R04 | 表单 | 短信验证码 | 输入 | 绑定 code | 仅本地 | 仅本地 |
| R05 | 表单 | 获取验证码 | 点击 | 发码 + 60s 倒计时 | `GET /captcha` → token；`POST /auth/send-code` `{phone,captchaToken}` | 已接（captcha siteKey 常空 → fallback） |
| R06 | 表单 | 密码 / 确认密码 | 输入 | 强度 UI | 仅本地校验 | 仅本地 |
| R07 | 表单 | 显示密码 | 点击 | 切换 | 仅本地 | 仅本地 |
| R08 | 表单 | 同意协议 Toggle | 开关 | 控制提交可点 | 仅本地 | 仅本地 |
| R09 | 表单 | 注册并登录 | 点击 | register + 入会话 | `POST /auth/register` `{phone,code,password,…}` | 已接 |
| R10 | Alert | 确定 | 点击 | 关闭 | 仅本地 | 仅本地 |
| R11 | [预览] | 获取验证码 / 注册 | 点击 | No-op | 同 R05/R09 | 预览 |

**后端须支持：** 无正式 SMS/captcha 时的显式 fallback（如 `AUTH_SMS_FALLBACK=1`）或配置真实供应商。

---

# 03 · 发现 DiscoverView + DemandDetailView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| D01 | (auto) | 进入页 | 加载列表 | 列表填充 | `GET /demands/search?page&limit&stage=active` | 已接（生产 `DiscoverView(repository:)`；fixtures 仅设计预览） |
| D02 | 列表头 | 仅附近 / 筛选 | 点击 | 服务端附近搜（默认上海坐标+20km） | `GET /demands/search?lat&lng&distance` | 已接（设计预览本地滤） |
| D03 | 搜索框 | 关键词回车/放大镜 | 提交 | 服务端关键词 | `GET /demands/search?keyword=` | 已接（设计预览本地滤） |
| D04 | 列表 | 需求行 | 点击 | 选中详情 | 仅本地选中；详情可 `GET /demands/:id` | 已接刷新路径 |
| D05 | 错误 | 重新加载 | 点击 | 重拉列表 | 同 D01 | 已接 |
| D06 | 详情工具栏 | 刷新 | 点击 | 重拉详情 | `GET /demands/:id` | 已接（previewMode 隐藏） |
| D07 | 详情工具栏 | 收藏 / 已收藏 | 点击 | 切换收藏 | `POST /users/favorites/:demandId`（toggle） | 已接 |
| D08 | 更多菜单 | 分享… | 点击 | 复制深链到剪贴板 | `https://tothetomorrow.com/demands/:id`（系统分享） | 已接 |
| D09 | 更多菜单 | 举报… | 点击 | Report Sheet | `POST /reports` `{targetUserId,demandId,category,reason}` | 已接 |
| D10 | 底栏 | 请求接单 | 点击 | 打开申请 Sheet | 仅本地 | 仅本地 |
| D11 | 底栏 | 收藏 | 点击 | 同 D07 | 同 D07 | 已接 |
| D12 | 申请 Sheet | 理由 TextEditor | 输入 | 本地 | 仅本地 | 仅本地 |
| D13 | 申请 Sheet | 取消 | 点击 | dismiss | 仅本地 | 仅本地 |
| D14 | 申请 Sheet | 提交请求 | 点击 | 提交申请 | `POST /demands/:id/request` `{message?}` | 已接 |
| D15 | 附件 | 媒体链接 | 点击 | 打开 URL | 详情须返回 `mediaUrls` | 已接字段 |
| D16 | Alert | 确定 | 点击 | 关反馈 | 仅本地 | 仅本地 |

**详情响应后端必须字段：** `deposit` / `amountEstimate` / `mediaUrls` / `lifecycleStage` / `visibleUntil|expireAt` / 申请人相关。

---

# 04 · 卡池 CardPoolView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| C01 | Tab | 进行中 | 点击 | 加载活跃池 | `GET /demands/active?page&pageSize` | 已接 |
| C02 | Tab | 死池 | 点击 | 加载死池 | `GET /demands/dead?page&pageSize` | 已接 |
| C03 | 工具栏 | 刷新 | 点击 | 重载当前池 | 同 C01/C02 | 已接 |
| C04 | 工具栏 | 服务卡 | 点击 | Sheet 我的服务卡 | `GET /service-cards/mine` | 已接 |
| C05 | Sheet | 关闭 / 刷新 | 点击 | dismiss / 重载 | 同 C04 | 已接 |
| C06 | 筛选 | 搜索 | 输入 | 客户端过滤 | 可选服务端 | 仅本地 |
| C07 | 筛选 | 类目 / 服务模式 / 排序 Menu | 选择 | 客户端 | 可选服务端 | 仅本地 |
| C08 | 筛选 | 筛选图标按钮 | 点击 | No-op | 高级筛选 | **缺失** |
| C09 | 列表 | 需求行 | 点击 | 选中详情 | 仅本地 | 仅本地 |
| C10 | 分页 | 页码 / 上一页 / 下一页 | 点击 | 本地分页或重请求 | 与 C01 分页参数一致 | 部分本地 |
| C11 | 错误 | 重新加载 | 点击 | 重载 | 同 C01/C02 | 已接 |
| C12 | 活跃详情 CTA | 参与应标 | 点击 | 打开报价 Sheet → 提交 | `POST /demands/:id/bid` `{price,message?}`（**不成单**；后端已允 ACTIVE/PENDING） | 已接（设计预览 No-op） |
| C13 | 活跃详情 | 查看我的服务卡 | 点击 | 同 C04 | 同 C04 | 已接 |
| C14 | 死池详情 | 抢单 | 点击 | 抢单 | `POST /demands/:id/snatch`（死池含 completed / 过期 ACTIVE 等） | 已接 |
| C15 | 工具栏 | 抢单额度 | (auto) 展示 | 「抢单额度 N」 | `GET /users/snatch-status` → `snatchCredits` | 已接 |

---

# 05 · 发布 CreateDemandView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| P01 | 顶栏 | 保存草稿 | 点击 | 本地成功条 | 草稿持久化 API | **缺失**（现仅本地） |
| P02 | 工具栏 | 取消 | 点击 | dismiss（非嵌入） | 仅本地 | 仅本地 |
| P03 | 表单 | 标题 | 输入 | draft | 提交字段 `title` | 仅本地→提交 |
| P04 | 表单 | 期望效果 | 输入 | draft | `expectedOutcome` | 同上 |
| P05 | 表单 | 详细描述 | 输入 | draft | `description` | 同上 |
| P06 | 表单 | 最低保障金额 | 输入 | draft | `minPrice` | 同上 |
| P07 | 表单 | 期望预算 | 输入 | draft | `amountEstimate` | 同上 |
| P08 | 表单 | 完成时限 DatePicker | 选择 | deadline | `timeLimit` / expire 相关 | 同上 |
| P09 | 表单 | 服务人数 −/+ | 点击 | 调整人数 | `maxApplicants` | 同上 |
| P10 | 表单 | 标签 Menu / 移除 chip | 选/删 | ≤5 标签 | 提交 `tags`；元数据 `GET /tags` | 元数据已接 |
| P11 | 表单 | 服务方式 线上/线下 | 分段 | 附近发现开关 | `serviceType` OFFLINE/ONLINE | 同上 |
| P12 | 表单 | 地区 Picker | 选择 | regionId | `GET /regions`；提交 `regionId` | 已接 |
| P13 | 表单 | PhotosPicker 上传 | 选图 | 本地 multipart 缓存 | 随发布上传；字段名 **`files`**（兼兼容 `images`/`video`） | 提交时已接 |
| P14 | 表单 | 移除附件 | 点击 | 删本地文件 | 仅本地 | 仅本地 |
| P15 | 表单 | 仅认证服务者 | Toggle | 标志 | `isCertifiedOnly`（multipart 布尔勿把 `"false"` 当 true） | 同上 |
| P16 | 预览栏 | 确认并发布 | 点击 | 生产：`frontendPreview=false` → multipart 发布 | `POST /demands` multipart + `Idempotency-Key`；响应含 `depositRequired` 等 | 已接（仅设计预览本地绕过） |
| P17 | 预览栏 | 存为草稿 | 点击 | 保存 DRAFT | `POST /demands/drafts`（multipart/JSON） | 已接（设计预览本地 toast） |
| P18 | Alert | 确定 | 点击 | 关错 | 仅本地 | 仅本地 |

**后端发布后必须：** 扣托管、写钱包流水、返回可展示的托管金额与规则版本。

---

# 06 · 圈子 CirclesView

## 6.1 列表与 Sheet

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| CIR01 | (auto) | 进入 | 拉我的圈 | 列表 | `GET /circles/my` | 已接 |
| CIR02 | 顶栏 | 邀请码加入 | 点击 | Join Sheet | 仅本地打开 | 仅本地 |
| CIR03 | 顶栏 | 创建 | 点击 | Create Sheet | 仅本地打开 | 仅本地 |
| CIR04 | 顶栏 | 刷新 | 点击 | 重载 | `GET /circles/my` | 已接 |
| CIR05 | 范围 Menu | 我加入的 / 我创建的 | 选择 | 客户端过滤 | 仅本地 | 仅本地 |
| CIR06 | 搜索 | 搜索圈子 | 输入 | 客户端过滤 | 仅本地 | 仅本地 |
| CIR07 | 列表 | 圈子行 | 点击 | 选中详情 | 仅本地；详情见下 | 仅本地 |
| CIR08 | 空态 | 邀请码加入 / 创建私人圈 | 点击 | 同 CIR02/03 | 同上 | 仅本地 |
| CIR09 | Join Sheet | 邀请码 | 输入 | 本地 | 仅本地 | 仅本地 |
| CIR10 | Join Sheet | 取消 | 点击 | dismiss | 仅本地 | 仅本地 |
| CIR11 | Join Sheet | 加入 | 点击 | 加入 | `POST /circles/join-by-code` `{code}` | 已接 |
| CIR12 | Create Sheet | 名称 / 描述 | 输入 | 本地 | 仅本地 | 仅本地 |
| CIR13 | Create Sheet | 取消 / 创建 | 点击 | dismiss / 创建 | `POST /circles` `{name,description}` | 已接 |

## 6.2 详情 Hub（真路径）

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| CIR14 | (auto) | 选中圈 | 拉 Hub | 面板数据 | `GET /circles/:id` · `/hub/home` · `/members` · `/resources` · `/hub/activities` · `/analytics` | 已接 |
| CIR15 | Tab | 概览/成员/资源/动态/分析/管理 | 点击 | 切 Tab | analytics 懒加载 | 已接 |
| CIR16 | 头 | 复制邀请码 | 点击 | 剪贴板 | 仅本地 | 仅本地 |
| CIR17 | 头 | 加入圈子 | 点击 | 加入 | `POST /circles/:id/join` | 已接 |
| CIR18 | 成员 Menu | 设为管理员 / 降为成员 | 点击 | 改角色 | `PATCH /circles/:id/members/:userId` | 已接 |
| CIR19 | 成员 Menu | 移出 | 点击 | 踢人 | `DELETE /circles/:id/members/:userId` | 已接 |
| CIR20 | 管理 | 公告 + 置顶 + 发布 | 提交 | 发公告 | `POST /circles/:id/hub/announcements` | 已接 |
| CIR21 | 管理 | 邮箱 + 发送邀请 | 提交 | 邮件邀请 | `POST /circles/:id/invites` `{email}` | 已接 |
| CIR22 | 管理 | 圈子心跳 | 点击 | 心跳 | `POST /circles/:id/hub/heartbeat` | 已接 |
| CIR23 | 管理 | 重置邀请码 | 点击 | 新码 | `POST /circles/:id/invite-code/reset` | 已接（预览常 No-op） |
| CIR24 | 资源 | 下载链接 | 点击 | 打开 URL | 资源 URL 由列表返回 | 已接只读 |
| CIR25 | — | 离开圈子 | （若有入口） | 离开 | `POST /circles/:id/leave` | 有 API |
| CIR26 | [预览] | 邀请成员 / 重置码 | 点击 | No-op | 同 CIR21/23 | 预览未接 |

---

# 07 · 自然回 NaturalLoopWorkspaceView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| NL01 | 顶栏 | 系统能力 | 点击 | 能力目录 Sheet | `GET /loops/capabilities` | 已接 |
| NL02 | Sheet | 关闭 / 刷新 | 点击 | dismiss / 重拉 | 同 NL01 | 已接 |
| NL03 | 顶栏 | 刷新 | 点击 | 重拉 offerings / mine | `GET /loops/offerings` · `GET /loops/runs/mine` | 已接（设计预览 No-op） |
| NL04 | 列表 | 搜索 offering | 输入 | 客户端过滤 | 仅本地 | 仅本地 |
| NL05 | 列表 | Offering 卡 | 点击 | 选中 | 仅本地；详情可 `GET /loops/offerings/:id` | 有 API |
| NL06 | 执行区 | URL 输入 | 输入 | 本地 | 作为 run input | 仅本地→运行 |
| NL07 | 执行区 | 清除 URL | 点击 | 清空 | 仅本地 | 仅本地 |
| NL08 | 执行区 | 提取说明 | 输入 | 本地 note | run input | 仅本地→运行 |
| NL09 | 执行区 | 运行 | 点击 | 发起 run | `POST /loops/offerings/:id/run` `{demandId?,input}` | 已接（设计预览 No-op） |
| NL10 | 最近运行 | 运行行 | 点击 | 选中结果 | `GET /loops/runs/:id` · `/events` | 已接 |
| NL11 | 最近 | 查看全部运行记录 | 点击 | 重拉 mine | `GET /loops/runs/mine` | 已接（设计预览 No-op） |
| NL12 | 结果 | 重试核验 | 点击 | 重试 | `POST /loops/runs/:id/retry-verification` | 已接（设计预览 No-op） |
| NL13 | 结果 | 查看完整结果 | 点击 | 展示详情 | 同 NL10 | 已接 / 预览弱 |
| NL14 | （死代码路径） | 意图推荐 | — | — | `GET /loops/recommend` | 有 API |
| NL15 | — | 按需求查 runs | — | 无 UI | `GET /loops/runs?demandId=` | 有 API 无入口 |

---

# 08 · 找人 FindPeopleView

> 生产始终用 **08 渲染图工作台**（`FindPeopleReferencePreview`），布局不动；`previewUsers == nil` 时从库拉同一视觉结构的数据。  
> 种子：`seed-macos-find-people-preview.sql` 固定 UUID `00000008-0001-…`～`0008`（陈知远、周屿、程野、乔安、林夏、许言、方舟、张默）。

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| FP01 | Tab | 搜索 / 认证服务者 | 点击 | 切 Tab；live 重拉列表 | 仅本地 + 重载 | 已接 |
| FP02 | (auto) | 进入页 | 加载人选 | 卡片列表 | 优先 `GET /users/:id`×种子 UUID；空则 `GET /certification/providers`；DTO 含 SoftUser 字段 + `isFollowing` | 已接（设计预览 fixtures） |
| FP03 | 搜索 | NWSearchBar 回车 | 提交 | 服务端搜索结果 | 搜索 Tab：`GET /users/search?keyword=`；认证 Tab：`GET /certification/providers?tags=`；清空则恢复种子/providers | 已接（设计预览仍本地滤） |
| FP04 | 筛芯片 | 标签 / 地区 Menu | 选择 | 服务端筛选 | `searchByTags` / `providers?tags&regionId` | 已接（设计预览本地） |
| FP05 | 筛 | 重置 / 筛选 | 点击 | 清空或重搜 | 同 FP04 | 已接 |
| FP06 | 结果 | 网格/列表布局 | 点击 | 布局切换 | 仅本地 | 仅本地 |
| FP07 | 卡片 | 人选 | 点击 | 详情面板 + 刷新关注态 | `GET /users/:id`（可选鉴权 → `isFollowing`） | 已接 |
| FP08 | 详情 | × 关闭 | 点击 | 关面板 | 仅本地 | 仅本地 |
| FP09 | 详情 | 发消息 | 点击 | `navigation.openDirectMessage` | 打开私信会话（发送仍走消息页 `POST /messages/send`） | 已接（设计预览禁用） |
| FP10 | 详情 | +关注 / 已关注 | 点击 | follow 切换 | `POST /users/:id/follow` · `DELETE /users/:id/follow` | 已接（设计预览本地 toggle） |

---

# 09 · 消息 · 私聊 MessagesView (direct)

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| M01 | (auto) | 进入 | 会话列表 | 列表 | `GET /messages/conversations` | 已接 |
| M02 | 头 | 私聊 / 群聊 pills | 点击 | 切 InboxMode | 仅本地 | 仅本地 |
| M03 | 搜索 | 「搜索会话」 | — | 装饰、未绑定 | 会话/用户搜索 | **缺失** |
| M04 | 列表 | 会话行 | 点击 | 打开聊天 | `GET /messages/:userId?page=` | 已接 |
| M05 | 错误 | 重新加载 | 点击 | 重拉会话 | 同 M01 | 已接 |
| M06 | 聊头 | 延长 5 分钟 | 点击 | 延长沟通窗 | `POST /demands/:id/extend-comm` | 已接（预览常 No-op） |
| M07 | 输入 | + / 附件 | 点击 | 选卡发送 | `POST /messages/card-attachment` | 已接（预览弱） |
| M08 | 输入 | 需求卡快捷 | 点击 | 同 M07 | 同 M07 | 已接/预览 |
| M09 | 输入 | 文本框 + Enter | 输入/回车 | 发送 | `POST /messages/send` `{toUserId,content}` | 已接 |
| M10 | 输入 | 发送 | 点击 | 同 M09 | 同 M09 | 已接 |
| M11 | 气泡 | 需求卡/服务卡 | 点击 | 深链详情 | `GET /demands/:id` / `GET /service-cards/:id` | 已接 |
| M12 | Socket | (auto) | 增量消息 | 刷新收件箱 | Socket.IO 事件 | 部分实现 |
| M13 | 右侧信息 | 静态链接 | — | 多为装饰 | 对方资料等 | 预览弱 |

---

# 11 · 消息 · 群聊 (merge)

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| G01 | (auto) | 群聊 Tab | 拉群列表 | 列表 | `GET /messages/merge` | 已接 |
| G02 | 工具栏 | 通知 | 点击 | 通知 Sheet | `GET /messages/notifications` | 已接入口 |
| G03 | 工具栏 | 新建群聊 | 点击 | Create Sheet | 仅本地打开 | 仅本地 |
| G04 | 工具栏 | 刷新 | 点击 | 重拉 | 同 G01 | 已接 |
| G05 | Create | 群名 | 输入 | 本地 | 仅本地 | 仅本地 |
| G06 | Create | 成员 Toggle | 开关 | 选成员 | 仅本地 | 仅本地 |
| G07 | Create | 取消 / 创建 | 点击 | dismiss / 建群 | `POST /messages/merge` `{title,memberIds}` | 已接 |
| G08 | 列表 | 群行 | 点击 | 打开群聊 | `GET /messages/merge/:id?page=` | 已接 |
| G09 | 输入 | 文本 + 发送 | 发送 | 发群消息 | `POST /messages/merge/:id/send` `{content}`（可 multipart `file`） | 已接 |
| G10 | 输入 | + / 文件图标 | 点击 | 可选附件发送 | 同 G09 multipart | 部分（UI 弱于私信） |
| G11 | 右侧 | 添加成员 | 点击 | Sheet 选关注用户 | `POST /messages/merge/:id/members` `{userIds}` | 已接 |
| G12 | 右侧 Tab | 群信息 / 群设置 | 点击 | 本地 Tab | 仅本地 | 仅本地 |
| G13 | 右侧 | 共享文件列表 | (auto) | 聚合附件消息 | `GET /messages/merge/:id/files` | 已接 |
| G14 | 右侧 | 消息免打扰 | Toggle | 写 mute | `PUT /messages/merge/:id/mute` `{muted}` | 已接 |
| G15 | 右侧 | 退出群聊 | 点击 | 退群并刷新列表 | `DELETE /messages/merge/:id/members/me` | 已接 |

---

# 10 · 认证 CertCenterView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| CERT01 | (auto) | 进入真表单 | 状态 | 展示等级/信用 | `GET /users/cert-status` | 已接 |
| CERT02 | 标签 | FlowTagPicker | 选择 | 本地集合 | `GET /tags` | 已接 |
| CERT03 | 地区 | Picker | 选择 | regionId | `GET /regions` | 已接 |
| CERT04 | 按钮 | 提交认证申请 | 点击 | 注册技能+证明 | `POST /certification/register` `{tags,regionId,proofUrls?}` | 已接 |
| CERT05 | 按钮 | 尝试升级等级 | 点击 | 升级 | `POST /users/upgrade-cert` | 已接 |
| CERT06 | [预览] | + 添加标签 | 点击 | No-op | 同 CERT04 | 预览 |
| CERT07 | [预览] | 服务模式/区域下拉 | — | 展示 | 扩展字段 | **缺失完整契约** |
| CERT08 | 证明资料 | PhotosPicker | 选图上传 | 得 URL 并入注册 | `POST /certification/uploads/proof` → `proofUrls` | 已接（设计预览本地格） |
| CERT09 | [预览] | 更新认证资料 | 点击 | No-op | 同 CERT04 | 预览 |
| CERT10 | [预览] | 申请升级 | 点击 | No-op | 同 CERT05 | 预览 |
| CERT11 | [预览] | 查看帮助文档 | 点击 | No-op | 跳帮助 | 仅本地导航 |

---

# 12 · 我的 ProfileView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| PR01 | 二级导航 | 各子项 | 点击 | 切子页 | 仅本地 | 仅本地 |
| PR02 | 折叠轨 | 图标 | 点击 | 快捷导航 | 仅本地 | 仅本地 |
| PR03 | 概览 | 忙碌中 Toggle | 开关 | 更新忙碌 | `GET/PUT /users/busy` | 已接（预览可本地） |
| PR04 | 概览 | 进行中订单卡 | 点击 | → 订单 | 列表见 O* | 仅本地导航 |
| PR05 | 概览 | 托管余额卡 | 点击 | → 钱包 | `GET /wallet/balance`（概览加载） | 已接 |
| PR06 | 概览 | 未读消息卡 | 点击 | → 通知 | unread / notifications | 导航 |
| PR07 | 概览 | Natural Loop 卡 | 点击 | → 自然回 | runs/mine | 导航 |
| PR08 | 近期活动 | 各行 | 点击 | 跳转子页 | 仅本地 | 仅本地 |
| PR09 | 快捷 | 编辑资料 | 点击 | → 设置 | 见 SET* | 仅本地 |
| PR10 | 快捷 | 查看钱包 | 点击 | → 钱包 | 见 W* | 仅本地 |
| PR11 | (auto) | 概览加载 | — | busy + wallet | `GET /users/busy` · `GET /wallet/balance` | 已接 |
| PR12 | 身份 | 头像昵称信用 | 展示 | — | `GET /users/me` / auth me | 已接 |

---

# 13 · 订单 OrdersListView / OrderDetailView

## 13.1 列表

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| O01 | (auto) | 进入 | 列表 | — | `GET /orders?page&role?` | 已接 |
| O02 | 工具栏 | 刷新 | 点击 | 重拉 | 同 O01 | 已接 |
| O03 | 筛选 | 角色 全部/需求方/服务方 | 选择 | 重拉 | `role` 查询参数 | 已接（预览多本地） |
| O04 | 筛选 | 阶段 Menu/分段 | 选择 | 过滤 | 客户端或 `stage` 参数 | 部分本地 |
| O05 | 列表 | 订单行 | 点击 | 详情 | 仅本地选中；可 `GET /orders/:id` | 已接 |

## 13.2 详情动作（真路径，受 OrderActionPolicy）

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| O06 | 动作 | 支付平台服务费 / 确认预付 | 点击 | 打开预付 Sheet → 真扣款 | 先 `GET /orders/:id/pay-breakdown` 再 `POST /orders/:id/prepay` | 已接（设计预览假成功） |
| O07 | 动作 | 标记服务完成 | 点击 | 完成 | `POST /orders/:id/complete` | 已接 |
| O08 | 动作 | 部分完成并结算 | 点击 | Partial Sheet | `POST /orders/:id/partial` `{newPrice,description}` | 已接 |
| O09 | 动作 | 确认完成并付款 | 点击 | 验收 | `POST /orders/:id/confirm` | 已接 |
| O10 | 动作 | 提交争议 | 点击 | 争议 Sheet → 上传+提交 | `POST /orders/:id/dispute` + 证据 | 已接（设计预览本地） |
| O11 | 动作 | 取消订单 | 点击 | 取消 | `POST /orders/:id/cancel` | 已接 |
| O12 | 动作 | 评价本次服务 | 点击 | Review Sheet | `POST /reviews` `{orderId,rating,content?}` | 已接 |
| O13 | 动作 | 刷新订单状态 | 点击 | 重拉 | `GET /orders/:id` | 已接 |
| O14 | 明细 | 结算明细 Disclosure | 展开 | 展示 | 金额字段来自订单 DTO / pay-breakdown | 已接字段策略 |
| O15 | [预览] | 取消 / 确认预付 / 需求链 | 点击 | No-op | 同 O06/O11 | 预览 |
| O16 | [预览] | 订单内聊天输入 | — | 装饰 | 订单会话或复用私信 | **缺失** |

### PartialCompleteSheet

| # | 控件 | 操作 | 后端 |
|---|------|------|------|
| O17 | 已完成金额 / 说明 | 输入 | 仅本地直至提交 |
| O18 | 确认部分结算 | 点击 | `POST /orders/:id/partial` |

### ReviewOrderSheet

| # | 控件 | 操作 | 后端 |
|---|------|------|------|
| O19 | 评分 Stepper / 评论文本 | 输入 | 仅本地直至提交 |
| O20 | 提交评价 | 点击 | `POST /reviews` |

---

# 14 · 我的需求 MyDemandsView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| MD01 | (auto) | 进入 | 列表 | — | `GET /demands/my` | 已接 |
| MD02 | 工具栏 | 刷新 | 点击 | 重拉 | 同 MD01 | 已接 |
| MD03 | 列表 | 需求行 | 选中 | 拉申请人/应标 | `GET /demands/:id/applicants-v2` · `GET /demands/:id/bids` | 已接 |
| MD04 | 详情 | 撤回需求 | 点击 | 撤回 | `POST /demands/:id/withdraw` | 已接 |
| MD05 | 详情 | 永久删除 | 点击→确认 | 删除冻结需求 | `DELETE /demands/:id`（仅 FROZEN） | 已接 |
| MD06 | 确认框 | 取消 / 确认删除 | 点击 | dismiss / 删 | 同 MD05 | 已接 |
| MD07 | 详情 | 打开详情 | 导航 | DemandDetailView | `GET /demands/:id` | 已接 |
| MD08 | 申请人 | 接受 | 点击 | 成单提示 | `POST /demands/:id/accept/:applicantId` | 已接 |
| MD09 | 申请人 | 拒绝 | 点击 | 拒绝 | `POST /demands/:id/reject/:applicantId` | 已接 |
| MD10 | [预览] | 状态 Tab | 点击 | 本地滤 | 可选服务端 stage | 仅本地 |
| MD11 | [预览] | 发布新需求 | 点击 | No-op | 跳转发布 / POST demands | **未接** |
| MD12 | [预览] | 撤回/删除/接受/拒绝/下载 | 点击 | No-op | 同 MD04–09 | 预览 |

---

# 22 · 我的应标 MyBidsView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| BID01 | (auto) | 进入 | 列表 | — | `GET /demands/my-applications` | 已接 |
| BID02 | 工具栏 | 刷新 | 点击 | 重拉 | 同 BID01 | 已接 |
| BID03 | 列表 | 行/卡 | 选中 | 需求详情 | `GET /demands/:id` | 已接 |
| BID04 | [预览] | 状态 Tab | 点击 | 本地滤 | 可选状态筛选参数 | 仅本地 |
| BID05 | 详情 | 撤回应标 | 点击 | 撤回 PENDING 申请 | `POST /demands/applications/:applicationId/withdraw` | 已接（需 `applicationId`） |
| BID06 | [预览] | 打开需求 | 点击 | No-op | 导航详情 | 预览未接 |

---

# 15 · 钱包 WalletView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| W01 | (auto) | 进入 | 摘要+流水 | — | `GET /wallet/balance` · `GET /wallet/ledger?page&limit` | 已接 |
| W02 | 摘要 | 充值 | 点击 | 模拟充值 Sheet | `POST /wallet/recharge` `{amount}`（模拟点数） | 已接 |
| W03 | Sheet | 确认/取消 | 点击 | 入账/关闭 | 同 W02 | 已接 |
| W04 | 流水 | 刷新 | 点击 | 重拉 | 同 W01 | 已接 |
| W05 | 流水 | 加载更多 | 点击 | 下一页 | `GET /wallet/ledger` 分页 | 已接 |
| W06 | [预览] | 类型 pills | 点击 | UI 滤（弱） | `type` 查询参数 | **可增强** |
| W07 | 流水 | 行点击 | 点击 | 右侧详情抽屉 | ledger 行字段拼装（无 `:id` 专用接口） | 已接 |
| W08 | 抽屉 | 关闭 | 点击 | 关 | 仅本地 | 仅本地 |
| W09 | 抽屉 | 复制交易号等 | — | 本地 | 仅本地 | 可增强 |
| W10 | 摘要 | 提现 | 点击 | 模拟提现 Sheet | `POST /wallet/withdraw` `{amount}`（模拟） | 已接 |

---

# 16 · 服务卡 ServiceCardsManageView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| SC01 | Mode | 我的 / 市场 | 切换 | 重载 | `GET /service-cards/mine` · `GET /service-cards/search` | 已接 |
| SC02 | 工具栏 | 新建 | 点击 | 编辑 Sheet | 仅本地打开 | 仅本地 |
| SC03 | 工具栏 | 刷新 | 点击 | 重载 | 同 SC01 | 已接 |
| SC04 | 市场 | 搜索框 Enter | 提交 | 搜索 | `GET /service-cards/search?keyword&limit` | 已接 |
| SC05 | 列表 | 卡行 | 选中 | 详情 | `GET /service-cards/:id`（可选） | 有 API |
| SC06 | 我的详情 | 编辑 | 点击 | 编辑 Sheet | 仅本地打开 | 仅本地 |
| SC07 | 我的详情 | 发布 | 点击 | 上架 | `POST /service-cards/:id/publish` | 已接 |
| SC08 | 我的详情 | 下架 | 点击 | 下架 | `POST /service-cards/:id/unpublish` | 已接 |
| SC09 | Editor | 标题/摘要/描述/分类/最低价 | 编辑 | 表单 | 提交字段 | 仅本地→保存 |
| SC10 | Editor | 取消 | 点击 | dismiss | 仅本地 | 仅本地 |
| SC11 | Editor | 创建 / 保存 | 点击 | 写卡 | `POST /service-cards` · `PATCH /service-cards/:id` | 已接 |
| SC12 | [预览] | 新建/下架/编辑/查看详情 | 点击 | No-op | 同上 | 预览 |
| SC13 | — | 标签/最高价/交付方式完整编辑 | — | UI 简化 | 扩展字段 | **部分缺失** |

---

# 17 · 通知 NotificationsView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| N01 | (auto) | 进入 | 列表 | 生产拉 API | `GET /messages/notifications?page=` | 已接（fixtures 仅设计预览） |
| N02 | 头 | 全部标为已读 | 点击 | 全标已读 | `POST /messages/notifications/read-all` | 已接 |
| N03 | 头 | 刷新 | 点击 | 重拉 | 同 N01 | 已接 |
| N04 | 列表 | 通知行 | 点击 | 详情 + 标已读 | `POST /messages/notifications/:id/read` | 已接 |
| N05 | 详情 | 标为已读 | 点击 | 标已读 | 同 N04 | 已接 |
| N06 | 详情 | 打开订单/需求/消息/认证/福利… | 点击 | `session.navigation` 深链 | `orderId` / `demandId` / `path` 字段 | 已接 |

---

# 18 · 福利 WelfareCenterView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| WEL01 | Tab | 任务 / 我的奖励 | 点击 | 切面板；奖励 Tab 拉 rewards | 仅本地 Tab；奖励见 WEL04 | 仅本地 / 已接 |
| WEL02 | (auto) | 任务列表 | 加载 | 列表 | `GET /welfare/demands` | 已接（fixtures 仅设计预览） |
| WEL03 | 列表 | 任务行 | 点击 | 详情 | 仅本地选中 | 仅本地 |
| WEL04 | 摘要 | 查看全部奖励记录 | 点击 | 切奖励 Tab + 加载 | `GET /welfare/rewards` | 已接 |
| WEL05 | 详情 | 领取任务 | 点击 | claim + 刷新 | `POST /welfare/claim/:demandId` | 已接 |
| WEL06 | — | 完成任务发奖 | 无完整 UI | — | 完成/发奖流程 | **部分缺失产品面** |

---

# 19 · 九木助手 AgentChatView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| A01 | (auto) | 进入 | 会话列表 | — | `GET /agent/conversations` | 已接 |
| A02 | 侧栏 | 展开/折叠 | 点击 | 宽度 | 仅本地 | 仅本地 |
| A03 | 侧栏 | 新对话 | 点击 | 创建并选中 | `POST /agent/conversations` `{title?,thinkMode?}` | 已接 |
| A04 | 侧栏 | 刷新 | 点击 | 重拉列表 | 同 A01 | 已接 |
| A05 | 列表 | 会话行 | 选中 | 拉详情 | `GET /agent/conversations/:id` | 已接 |
| A06 | 菜单 | 删除 | 点击 | 删会话 | `DELETE /agent/conversations/:id` | 已接 |
| A07 | 聊头 | 垃圾桶 | 点击 | 删当前 | 同 A06 | 已接 |
| A08 | 作曲 | 快速/深度思考 | Picker | 本地偏好 | stream 带 `thinkMode` | 已接 |
| A09 | 作曲 | 输入框 Enter | 发送 | 乐观 UI + 流 | `POST /agent/conversations/:id/stream` (SSE) | 已接 |
| A10 | 作曲 | 发送按钮 | 点击 | 同 A09 | 同 A09；失败可降级 `POST …/messages` | 已接 |
| A11 | 思考块 | 展开 | 点击 | 展示 thinking | 仅本地 | 仅本地 |
| A12 | 批准 Sheet | 拒绝 / 允许执行 | 点击 | 解工具挂起 | `POST /agent/conversations/:id/approve-tool` | 已接 |
| A13 | 工具结果 | navigate_to 成功 | (auto) | 主壳受控跳转 | 工具结果结构化字段 | 已接白名单 |
| A14 | [预览] | 前往需求创建 / 打开草稿 | 点击 | No-op | 同 navigate | 预览 |

---

# 20 · 设置 SettingsView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| SET01 | (auto) | 进入 | 填表 | — | `GET /users/me` · `/tags` · `/busy` · `/blocklist` · `GET /pushes/preferences` | 已接 |
| SET02 | 资料 | 更换头像/封面 | PhotosPicker | multipart 上传 | `PUT /users/profile` fields `avatar`/`cover` | 已接 |
| SET03 | 资料 | 昵称 / 简介 | 编辑 | 本地直至保存 | `PUT /users/profile` | 已接 |
| SET04 | 资料 | 忙碌 Toggle | 开关 | 即时保存 | `PUT /users/busy` | 已接 |
| SET05 | 标签 | 删除 chip / 添加 | 点/提交 | 写标签 | `PUT /users/tags` | 已接 |
| SET06 | 屏蔽 | 标签/关键词 | 编辑 | 本地直至保存 | `PUT /users/blocklist` | 已接 |
| SET07 | 推送 | 接收 Toggle / 频率 / 排除词标签 | 开关/编辑 | 即时或保存 | `PUT /pushes/preferences` | 已接 |
| SET08 | 底 | 保存 | 点击 | profile + blocklist + push | SET03 + SET06 + SET07 | 已接 |
| SET09 | 侧 | 用户协议/隐私/开源 | 导航 | 本地 LegalDoc | 仅本地（可改 CMS） | 仅本地 |
| SET10 | 侧 | 退出登录 | 点击 | 清会话 | `POST /auth/logout` | 已接 |

---

# 21 · 帮助 HelpView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| H01 | 分类列表 | 分类行 | 选中 | FAQ 列表 | 仅本地 `HelpFAQ` | 仅本地 |
| H02 | 条目列表 | 问题行 | 选中 | 文章 | 仅本地 | 仅本地 |
| H03 | 文内链接 | 托管规则/争议/钱包… | 点击 | `navigation.navigate` | `/settings` · `/orders` · `/transactions` | 已接 |

---

# 23 · 关注 FollowsView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| F01 | Tab | 关注 / 粉丝 | 点击 | 切列表并加载 | `GET /users/:id/following` · `/followers` | 已接（fixtures 仅设计预览） |
| F02 | 搜索 | NWSearchBar | 输入 | 本地过滤 | 仅本地 | 仅本地 |
| F03 | 列表 | 用户行 | 点击 | 详情 | `GET /users/:id`（可选） | 已接 |
| F04 | 详情 | 发消息 | 点击 | `openDirectMessage` | 打开私信 | 已接 |
| F05 | 详情 | 关注 / 取消关注 | 点击 | follow 切换 | `POST|DELETE /users/:id/follow` | 已接 |
| F06 | 详情 | 查看全部服务 | 点击 | No-op | 用户服务卡列表 | **缺失** |

---

# 24 · 收藏 FavoritesView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| FAV01 | Tab | 需求 / 服务卡 | 点击 | 各拉收藏列表 | `GET /users/favorites` · `GET /users/favorites/cards` | 已接 |
| FAV02 | 搜索 | NWSearchBar | 输入 | 本地滤 | 仅本地 | 仅本地 |
| FAV03 | 头 | 筛选 | 点击 | No-op | 筛选 API | **缺失** |
| FAV04 | 列表 | 行 | 点击 | 详情 | `DemandDetailView(previewMode: false)` → `GET /demands/:id` | 已接 |
| FAV05 | 底栏 | 请求接单 | 点击 | 申请 Sheet | `POST /demands/:id/request`（经详情） | 已接 |
| FAV06 | 底栏 | 取消/重新收藏 | 点击 | toggle | `POST /users/favorites/:demandId`（经详情） | 已接 |

---

# 25 · 争议 Sheet RejectEvidenceSheet

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| DIS01 | 入口 | 订单「提交争议」 | 点击 | 开 Sheet | 仅本地打开 | 仅本地 |
| DIS02 | 头 | × 关闭 | 点击 | dismiss | 仅本地 | 仅本地 |
| DIS03 | 原因 | TextEditor ≤500 | 输入 | 本地 | `reason` / `description` | 仅本地→提交 |
| DIS04 | 图片 | + / 删除缩略图 | 点 | 本地槽位 → 提交时上传 | `POST /orders/uploads/evidence` → URL | 已接（设计预览假数据） |
| DIS05 | 链接 | URL + 添加/移除 | 编辑 | evidenceLink | 并入 `evidenceUrls` | 同上 |
| DIS06 | 协议 | Checkbox | 开关 | 允许提交 | 仅本地 | 仅本地 |
| DIS07 | 底 | 取消 | 点击 | dismiss | 仅本地 | 仅本地 |
| DIS08 | 底 | 提交争议 | 点击 | 上传证据 + 提交 | `POST /orders/:id/dispute` `{reason,description,evidenceUrls}` | 已接（设计预览本地成功） |

---

# 26 · 预付 Sheet PaymentPrepayModal / PaymentSheet

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| PAY01 | 入口 | 支付平台服务费 | 点击 | 开 Sheet | 应先拉 breakdown | 入口已接策略 |
| PAY02 | (auto) | 打开 Sheet | 拉分项 | 金额展示 | `GET /orders/:id/pay-breakdown` | 已接（无 breakdown 禁止确认） |
| PAY03 | 失败条 | 重新获取 | 点击 | 重拉分项 | 同 PAY02 | 已接 |
| PAY04 | 协议 | Checkbox | 开关 | 可点支付 | 仅本地 | 仅本地 |
| PAY05 | 底 | 取消 | 点击 | dismiss | 仅本地 | 仅本地 |
| PAY06 | 底 | 确认支付 N 点 | 点击 | 扣款 + 刷新 | `POST /orders/:id/prepay`；刷新 `GET /wallet/balance` · `GET /orders/:id` | 已接（设计预览假成功） |
| PAY07 | [设计背板] | 联系服务方 / 留言 | 点击 | No-op | 私信/订单消息 | 预览 |

**硬规则：** 无有效 pay-breakdown 禁止确认；金额禁止客户端用 `minPrice` 自算。

---

# 认证检索 ProvidersSearchView

| # | 区域 | 控件 | 操作 | 前端效果 | 后端契约 | 状态 |
|---|------|------|------|----------|----------|------|
| PS01 | 搜索 | 标签查询 + 搜索 | 提交 | 列表 | `GET /certification/providers?tags&page`；fallback `GET /users/search` | 已接 |
| PS02 | 列表 | 用户行 | 选中 | UserProfileView | `GET /users/:id` | 已接 |

---

# 横切：所有页共用元数据

| # | 能力 | 触发 | 后端 |
|---|------|------|------|
| X01 | 标签目录 | 发布/认证选标签 | `GET /tags` |
| X02 | 地区目录 | 发布/认证选地区 | `GET /regions` · `/regions/search` |
| X03 | Captcha | 发短信前 | `GET /captcha` |
| X04 | 健康 | 登录不可达 | `/health/services` |
| X05 | 未读轮询 | 壳层 | `GET /messages/unread-count` |
| X06 | Socket | 消息页 | Socket.IO 鉴权连接 |

---

# 后端排期优先级（按操作缺口）

### P0 — 生产壳层主链（2026-07-18 已接通，作回归清单）

1. 登录 / 注册 / me / logout  
2. 发布需求（multipart `files` + 托管）  
3. 发现详情 · 请求接单 · 收藏  
4. 卡池：active/dead · **bid** · **snatch**  
5. 我的需求：申请人接受/拒绝 · 撤回 · 删除  
6. 订单：list/detail · **pay-breakdown · prepay** · complete · confirm · cancel · partial · review  
7. **争议：evidence upload + dispute**  
8. 钱包 balance + ledger  
9. 私信 conversations / send / history / unread + Socket  

### P1 — 已接通（2026-07-19）

- 找人筛芯片服务端化  
- 推送排除词/标签  
- 服务卡收藏  
- 发现 keyword / lat+lng+distance  
- 撤回应标  
- 认证证明材料上传  

### P2 — 已接通（2026-07-19；边界见上）

- 忘记密码（send-reset-code + reset-password）  
- 分享（剪贴板深链）/ 举报（`POST /reports`）  
- 需求草稿（DRAFT）  
- 头像/封面 multipart  
- 群聊：加人、退群、免打扰、共享文件列表（附件发送 UI 仍弱于私信）  
- 模拟充值 / 提现  
- 钱包流水详情抽屉（拼装 ledger 行）  
- 帮助深链  

### 仍弱 / 不做

- 真实支付通道（充提仅为模拟点数）  
- 认证 admin 人工审核工作台  
- 多国家码 / CMS 帮助正文  
- 协议文案可点（登录页）  

---

# 附录 · 复验记录（2026-07-19 00:10）

| 检查项 | 结果 |
|--------|------|
| 生产壳层 | `ContentView` → `MainShellView()` 无 `designPreview*` |
| 侧栏 IA | 主区·协作·账户；嵌套「我的」 |
| 新路由冒烟 | reset-password / favorites/cards / drafts / applications withdraw / wallet recharge·withdraw / merge mute·leave·members·files / cert proof → **200/201** |
| 客户端 | Discover 服务端搜、Settings 推送排除+头像、Login 重置密码、Demand 分享举报、Wallet 充提+详情、Help 深链、FindPeople 芯片、Favorites 服务卡、Publish 草稿、MyBids 撤标、Messages 群扩展、Cert 证明 |

脚本/种子：`scripts/cloud-migrate/seed-macos-*-demo.sql`、`seed-macos-find-people-preview.sql`；服务端备份 `*.bak-gaps-*`。

---

# 附录 · Service 路径速查

| Service | 主要路径 |
|---------|----------|
| AuthService | `/auth/login` `/auth/send-code` `/auth/send-reset-code` `/auth/reset-password` `/auth/register` `/auth/me` `/auth/logout` |
| DemandService | `/demands/search` `/active` `/dead` `/demands` `/drafts` `/demands/:id` `/request` `/bid` `/bids` `/snatch` `/applications/:id/withdraw` `/my` `/my-applications` … |
| OrderService | `/orders` `/orders/:id` `/prepay` `/pay-breakdown` `/complete` `/confirm` `/partial` `/cancel` `/dispute` `/orders/uploads/evidence` |
| WalletService | `/wallet/balance` `/wallet/ledger` `/wallet/recharge` `/wallet/withdraw` |
| MessageService | `/messages/conversations` `/messages/:userId` `/messages/send` `/unread-count` `/notifications*` `/card-attachment` `/messages/merge*` `/merge/:id/mute` `/members` `/files` |
| UserService | `/users/me` `/users/:id` `/search` `/follow` `/favorites` `/favorites/cards` `/profile` `/tags` `/busy` `/blocklist` `/snatch-status` · `/pushes/preferences` |
| ReportService | `/reports` |
| CircleService | `/circles/my` `/circles` `/join-by-code` hub/… |
| LoopService | `/loops/recommend` `/offerings` `/offerings/:id/run` `/runs*` … |
| AgentService | `/agent/conversations*` `/stream` `/messages` `/approve-tool` |
| WelfareService | `/welfare/demands` `/welfare/claim/:id` `/welfare/rewards` |
| Misc | `/service-cards*` `/certification/*` `/certification/uploads/proof` `/tags` `/regions` `/captcha` `/reviews` |

---

本文与 [`BUSINESS-INVENTORY.md`](./BUSINESS-INVENTORY.md) 互补：后者偏能力成熟度，本文偏 **控件级后端契约**。
