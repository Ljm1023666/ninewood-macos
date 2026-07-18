# Ninewood macOS 架构

> 状态：现行  
> 更新：2026-07-17  
> 范围：`ninewood-macos` 原生 SwiftUI 客户端

## 1. 定位

`ninewood-macos` 是 Ninewood 云端的原生 macOS 客户端，不是独立后端，也不是
Windows Electron 客户端的代码分支。用户、需求、订单、钱包、消息和自然回的权威
状态均来自共享云端 API。

客户端负责：

- macOS 原生导航、窗口、键盘和可访问性交互；
- 会话恢复、Keychain Token、网络与限流反馈；
- 将云端 DTO 映射为稳定的客户端领域模型；
- 在本地执行表单校验、动作门控和展示状态；
- 通过 Socket.IO 接收“数据可能变化”的提示，再从 API 获取权威数据。

客户端不得：

- 复制服务端的资金结算或资格判定；
- 根据旧文档推导押金、退款或服务费金额；
- 用本地乐观状态替代最终订单状态；
- 在无用户确认时静默发布人回或需求。

## 2. 分层

```text
SwiftUI View
    ↓ 绑定与用户意图
Feature Model
    ↓ 用例状态、加载、选择、错误
Repository
    ↓ 领域数据与命令入口
API Service / Mapper
    ↓ 路由、DTO、领域映射
APIClient / ChatRealtime
    ↓
Ninewood Cloud
```

### View

只负责布局、绑定、Sheet/Alert 展示和将用户意图转交给 Feature Model。

### Feature Model

使用 Observation 管理一个页面或流程的状态。列表加载、筛选、选中项保持和错误转换
应位于这里。已建立：

- `DiscoverFeatureModel`
- `DemandDetailFeatureModel`
- `OrdersFeatureModel`
- `OrderDetailFeatureModel`
- `MessagesFeatureModel`
- `ChatDetailFeatureModel`

### Repository

为客户端业务提供稳定入口，隐藏具体后端路由。已建立：

- `DemandRepository`
- `DemandPublishRepository`
- `OrderRepository`
- `MessageRepository`
- `UserRepository`
- `NaturalLoopRepository`

新 View 不得直接调用 `APIClient`。现有 View 对 `*Service` 的依赖应在修改相关功能时
迁移至 Repository。

### Domain

领域类型不依赖 SwiftUI。涉及资金、资格、发布或状态转换的客户端规则必须可以独立
测试。目前包括：

- `DemandDraft` / `DemandPublishCommand`
- `OrderActionPolicy`
- Natural Loop 领域模型和 Mapper

### Service 与 DTO

Service 对应服务端路由，只负责请求参数、响应 DTO 和必要映射，不保存页面状态。
DTO 应逐步按 Auth、Demand、Order、Message、Loop、Circle 等领域拆分。

## 3. 会话与依赖

`ServiceRegistry` 是唯一组合根。对象构造顺序为：

```text
APIClient
  ├─ API Services
  ├─ Repositories
  ├─ ChatRealtime
  ├─ InboxState
  └─ AuthSession
```

`AppSession` 是迁移期兼容门面。新功能优先依赖具体 Repository、`AuthSession` 或
`InboxState`，不得继续扩大 `AppSession` 的业务职责。

## 4. 错误与一致性

- 401：清除 Keychain Token、断开实时连接并回到登录态。
- 429：遵守 `Retry-After`，冷却期间不重复请求。
- 写操作：使用幂等键；失败时保留同一幂等键，成功后才生成新键。
- Socket.IO：只触发刷新，不作为订单、钱包或未读数的最终权威。
- DTO 解码失败：保留 Request ID 并显示可理解的错误，不伪装为空数据。

## 5. 测试

纯领域规则通过根目录 Swift Package 运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

应用构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project ninewood-macos.xcodeproj \
  -scheme ninewood-macos \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO
```

所有涉及发布、预付、结算、争议或删除的变更，除自动化测试外还必须执行
`QA-RUNBOOK.md` 中的人工确认检查。
