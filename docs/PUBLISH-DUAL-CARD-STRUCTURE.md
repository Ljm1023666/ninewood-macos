# macOS 正式产品结构 · 发布双卡工作台（2026-07-20）

## 决策

与 Windows `/publish` 对齐：侧栏「发布」**不再**直接进入完整发布表单，也不再由九木助手承担最终提交。

| 路径 | 页面 | 职责 |
|------|------|------|
| `/publish` | `PublishHubView` | 选择：需求卡 / 服务卡 → **开始用 AI 整理** |
| `/demands/create` | `PublishCardWorkspaceView(.demand)` | 对齐 Windows `DemandCreate`：左对话 + 右结构化字段 |
| `/service-cards/create` | `PublishCardWorkspaceView(.service)` | 同上（服务卡模式） |

## AI 整理（对齐 Windows `DemandCreate`）

- **Agent / Think**：`agent-demand-stream` + 旁路 `analyze-demand-stream`（`requirementState`）
- **Speed**：`analyze-demand`
- **Canvas**：`analyze-demand-stream` + 右侧卡牌预览
- **待补充队列**：勾选 missingInfo → 逐条回答 → 批量 `analyze-demand`
- **发布前置**：校验后弹出「确认匹配路径」再提交（对齐 `/demands/create/paths`）
- **会话草稿**：需求卡本地多会话恢复（UserDefaults）

## 关键文件

- `PublishCardWorkspaceView.swift` / `PublishWorkspaceFields.swift` / `PublishWorkspaceValidation.swift`
- `PublishWorkspaceSessionStore.swift` / `PublishWorkspaceExtras.swift`
- `PublishAIService.swift` / `PublishAIService+Stream.swift`
