# 九木 · Windows 端 Cursor 云端接入指南

> **读者：** Windows 仓库上的 Cursor / AI 助手，以及要把权限配到 Windows 机的人  
> **更新：** 2026-07-19  
> **背景：** macOS Cursor 已能 SSH 生产机；Windows Cursor 常见失败原因是**本机没有私钥 / 没有 OpenSSH / 防火墙**，不是服务器拒绝九木项目。  
> **安全：** 本文**不含**私钥内容、数据库密码、阿里云 AccessKey。密钥只走安全通道拷贝，**禁止 commit、禁止贴进公开聊天**。

---

## 0. 给 Windows Cursor 的一句话

你是 **Ninewood Windows 客户端**助手。权威后端在云上：

| 项 | 值 |
|----|-----|
| 生产 API | `https://tothetomorrow.com/api` |
| 生产主机 | `8.217.208.203`（Tailscale：`ninewood-prod` / `100.105.76.91`） |
| 云端代码 | `/opt/ninewood`（后端 `/opt/ninewood/server`） |
| 进程 | `pm2` 名 `ninewood`，端口 `3001` |
| 废弃主机 | **禁止**再改 `8.218.95.92` |

本仓库改的是 **Windows 客户端**；服务端改动在云上 `/opt/ninewood`。  
若本机尚无 SSH 密钥，**不要假装能登录**——按下文「首次配置」让用户放好密钥，或请 **Mac 端 Cursor** 代执行云端命令。

---

## 1. 分工：谁该改什么

| 角色 | 仓库 / 路径 | 职责 |
|------|-------------|------|
| Windows Cursor | Windows 客户端仓库（Electron 等） | UI、本地状态、调用生产 API、契约对齐 |
| macOS Cursor | `ninewood-macos` | 原生 macOS 客户端；本机常驻有 SSH 钥 |
| 云端 | `/opt/ninewood` | 共享 API / DB / Socket；两端共用 |

两端共享同一套 API，**不要各写各的假后端**。设计稿数据应进数据库（种子 SQL），不要只在客户端硬编码假列表。

---

## 2. 首次配置（人在 Windows 上做一次）

### 2.1 确认本机有 OpenSSH

PowerShell：

```powershell
Get-Command ssh
ssh -V
```

若没有：设置 → 应用 → 可选功能 → 安装 **OpenSSH 客户端**。

### 2.2 从 Mac 安全拷贝私钥（不要进 Git）

Mac 上私钥（已 gitignore）：

```text
~/Desktop/ninewood-macos/scripts/cloud-migrate/id_ed25519_ninewood
```

推荐放到 Windows：

```text
%USERPROFILE%\.ssh\id_ed25519_ninewood
```

PowerShell 示例（用 U 盘 / 局域网 / `scp` 均可，**勿**提交仓库）：

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
# 将私钥文件复制到：
#   $env:USERPROFILE\.ssh\id_ed25519_ninewood
icacls "$env:USERPROFILE\.ssh\id_ed25519_ninewood" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_ed25519_ninewood" /grant:r "$($env:USERNAME):(R)"
```

公钥已在服务器 `authorized_keys` 中，一般**不必**再传公钥。

### 2.3 连通性验证

**公网（优先）：**

```powershell
$KEY = "$env:USERPROFILE\.ssh\id_ed25519_ninewood"
ssh -i $KEY -o StrictHostKeyChecking=accept-new root@8.217.208.203 "hostname; pm2 list; curl -sS -o NUL -w '%{http_code}' http://127.0.0.1:3001/api/agent/provider"
```

**Tailscale（公网不通时）：**

1. Windows 安装并登录与 Mac 同一 Tailscale 账号  
2. 能 ping `ninewood-prod` 或 `100.105.76.91`  
3. SSH：

```powershell
ssh -i $KEY root@100.105.76.91 "hostname; pm2 list"
```

成功标志：能打印主机名，且 `pm2` 里有 `ninewood` / `online`。

### 2.4 给 Cursor 的本机规则（建议）

在 Windows 仓库 `.cursor/rules/` 增加一条（或用户规则），内容可引用本文路径，并写明：

```text
云服务器任务：有 shell 时自行 SSH，不要只甩命令给用户。
密钥：%USERPROFILE%\.ssh\id_ed25519_ninewood
主机：root@8.217.208.203（或 Tailscale 100.105.76.91）
云端根：/opt/ninewood ；pm2：ninewood ；API：https://tothetomorrow.com/api
禁止：改 8.218.95.92；把私钥/secrets 提交 Git；在云端填付费 LLM Key
AI：现阶段走 Mac Ollama（云端已转发）；Mac 关机则 AI 不可用，其它 API 正常
```

---

## 3. Windows Cursor 标准操作命令

把 `$KEY` 换成上面的私钥路径后直接执行。

### 3.1 登录 / 单条远程命令

```powershell
$KEY = "$env:USERPROFILE\.ssh\id_ed25519_ninewood"
ssh -i $KEY root@8.217.208.203
ssh -i $KEY root@8.217.208.203 'pm2 list; pm2 logs ninewood --lines 40 --nostream'
```

### 3.2 常用运维

```powershell
ssh -i $KEY root@8.217.208.203 @'
set -e
cd /opt/ninewood/server
pm2 list
pm2 logs ninewood --lines 80 --nostream
docker ps --format "table {{.Names}}\t{{.Status}}"
docker exec ninewood-postgres-1 psql -U ninewood -d ninewood -c "SELECT 1"
curl -sS http://127.0.0.1:3001/api/agent/provider | head -c 400
'@
```

### 3.3 上传补丁 / 种子 SQL

```powershell
$KEY = "$env:USERPROFILE\.ssh\id_ed25519_ninewood"
scp -i $KEY .\path\to\file.sql root@8.217.208.203:/tmp/
ssh -i $KEY root@8.217.208.203 'docker exec -i ninewood-postgres-1 psql -U ninewood -d ninewood < /tmp/file.sql'
```

macOS 仓库里已有可复用种子（可从 Git / 拷贝到 Windows）：

- `scripts/cloud-migrate/seed-macos-find-people-preview.sql`
- `scripts/cloud-migrate/seed-macos-design-content.sql`
- `scripts/cloud-migrate/seed-macos-chat-demo.sql`
- `scripts/cloud-migrate/seed-macos-discover-demo.sql`

原则与 macOS 一致：**设计稿内容进数据库，不要靠删客户端假数据「扫干净」。**

### 3.4 改服务端代码后

```powershell
ssh -i $KEY root@8.217.208.203 'cd /opt/ninewood/server && pm2 restart ninewood && pm2 logs ninewood --lines 30 --nostream'
```

改前先备份关键文件（例如 `cp file.ts file.ts.bak-$(date +%Y%m%d%H%M%S)`）。

---

## 4. 访问失败时怎么处理

| 现象 | 处理 |
|------|------|
| `Permission denied (publickey)` | 私钥路径错 / 权限过宽 / 拷错文件。重做 §2.2 |
| `Connection timed out` | 试 Tailscale IP；检查 Windows 防火墙 / 公司网 |
| Cursor Agent 无 shell 或禁网 | 让用户在本机终端跑验证命令；或请 **Mac Cursor** 代操作云端 |
| 只有 API、不需 SSH | 直接打 `https://tothetomorrow.com/api/...`；测试号见下方（密码勿写进公开文档时可向用户索取） |
| AI 接口失败 | 多半 Mac Ollama / Tailscale 掉线，与 Windows SSH 无关 |

### 协作话术（可复制给用户）

```text
我这边 Windows Cursor 暂时连不上 8.217.208.203（缺密钥或网络）。
请任选：
1) 按 docs/WINDOWS-CURSOR-CLOUD-ACCESS.md 把私钥放到 %USERPROFILE%\.ssh\id_ed25519_ninewood；或
2) 让 Mac 上的 Cursor 代执行云端命令：……
```

---

## 5. 客户端联调约定（Windows ↔ 云端）

1. **默认 API：** `https://tothetomorrow.com/api`（与 macOS 一致）  
2. **不要**再指向废弃机 `8.218.95.92`  
3. **鉴权：** Bearer Token；401 清会话，云端不可达时保留 Token 可重试  
4. **实时消息：** Socket.IO 跟生产同源；列表应用增量补丁，避免每条消息全量刷会话  
5. **测试账号：** 向用户确认当前联调号（macOS 侧常用 `19900001234`）；**不要**把密码写进仓库文档  
6. **AI：** 客户端不配 LLM Key；云端转发 Mac Ollama

---

## 6. 新会话开场白（Windows Cursor 可复制）

```text
读 docs/WINDOWS-CURSOR-CLOUD-ACCESS.md（或用户提供的同名桌面副本）。
我是九木 Windows 客户端助手。生产 API：https://tothetomorrow.com/api
云端：root@8.217.208.203:/opt/ninewood ，pm2：ninewood
私钥：%USERPROFILE%\.ssh\id_ed25519_ninewood
有 shell 时自行 SSH；连不上就说明原因并请 Mac Cursor 代操作，禁止碰 8.218.95.92。
```

---

## 7. 与 Mac 文档的关系

| 文档 | 给谁 | 是否含机密 |
|------|------|------------|
| 本文件 `docs/WINDOWS-CURSOR-CLOUD-ACCESS.md` | Windows Cursor / 可进 Git | **否** |
| Mac 桌面 `九木-新会话配置.md` | macOS Cursor | 否（路径指向本机钥） |
| Mac 桌面 `九木-云服务器权限与凭据.md` | 本人 / 可信 Mac 会话 | **是**（勿同步到 Windows 公开仓库） |

Windows 侧**只需要**本文件 + 私钥文件本身；不需要把「凭据全文」拷进 Windows 仓库。
