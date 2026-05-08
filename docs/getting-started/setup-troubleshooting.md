# SmartPerfetto 环境搭建与问题排查指南

本文档记录了在 WSL2 Ubuntu (glibc) 环境下搭建 SmartPerfetto 的完整过程、遇到的问题及其原因分析和解决方案。目标是：**换一个新环境后，按照此文档可以顺利搭建并处理常见问题**。

---

## 目录

1. [环境要求](#1-环境要求)
2. [快速搭建步骤](#2-快速搭建步骤)
3. [AI 模型配置](#3-ai-模型配置)
4. [问题与解决方案](#4-问题与解决方案)
   - 4.1 [trace_processor_shell 下载失败](#41-trace_processor_shell-下载失败google-luci-不可达)
   - 4.2 [文件上传大小限制 (MulterError: LIMIT_FILE_SIZE)](#42-文件上传大小限制-multererror-limit_file_size)
   - 4.3 [Claude Agent SDK musl 二进制兼容性问题](#43-claude-agent-sdk-musl-二进制兼容性问题ws2-glibc)
   - 4.4 [前端服务被意外终止](#44-前端服务被意外终止restart-backendsh-副作用)
   - 4.5 [AI 后端未连接](#45-ai-后端未连接)
   - 4.6 [局域网访问配置](#46-局域网访问配置)
5. [配置速查表](#5-配置速查表)
6. [验证清单](#6-验证清单)

---

## 1. 环境要求

| 组件 | 最低版本 | 说明 |
|------|---------|------|
| Node.js | v20+ | 推荐 v24.x（通过 nvm 安装） |
| npm | v10+ | 随 Node.js 安装 |
| git | v2+ | 克隆仓库 |
| WSL2 | - | Windows 下 Linux 开发环境（Ubuntu 22.04/24.04） |
| 磁盘空间 | ~5 GB | 依赖 + trace_processor_shell + 上传目录 |

**网络要求**：
- Google LUCI artifact server (`commondatastorage.googleapis.com`) 可能从国内/WSL2 环境无法直接访问
- 需要能访问 LLM API 代理地址（如 `https://llmapi.horizon.auto`）

---

## 2. 快速搭建步骤

### 2.1 克隆仓库

```bash
git clone https://github.com/Gracker/SmartPerfetto.git
cd SmartPerfetto
```

> 普通使用不需要初始化 `perfetto/` submodule。只有修改 AI Assistant 前端插件时才需要。

### 2.2 安装后端依赖

```bash
cd backend
npm install
cd ..
```

### 2.3 配置环境变量

```bash
cp backend/.env.example backend/.env
```

编辑 `backend/.env`，至少配置 AI 模型相关变量（详见[第 3 节](#3-ai-模型配置)）。

### 2.4 启动服务

```bash
./start.sh
```

首次启动会自动下载 `trace_processor_shell`。如果下载失败，参考 [4.1 节](#41-trace_processor_shell-下载失败google-luci-不可达)。

### 2.5 验证服务

| 检查项 | 命令/URL | 预期结果 |
|--------|---------|---------|
| 后端健康 | `curl http://localhost:3000/health` | `{"status":"OK",...}` |
| 前端 | 浏览器打开 `http://localhost:10000` | Perfetto UI 界面 |
| AI 配置 | health 响应中 `aiEngine.configured` | `true` |

---

## 3. AI 模型配置

SmartPerfetto 使用 Claude Agent SDK 作为 AI 运行时。有三种接入方式：

### 3.1 Claude Code 本地认证（零配置）

如果本机 `claude` 命令已经能正常工作（包括通过 Claude Code 配置了第三方 endpoint），可以不创建 `.env` 文件。SDK 会自动使用 Claude Code 的本地认证。

### 3.2 Anthropic 直连

```bash
ANTHROPIC_API_KEY=sk-ant-xxx
```

### 3.3 第三方 LLM 代理（最常用）

通过 Anthropic Messages 兼容代理接入 DeepSeek/GLM/Qwen/Kimi 等第三方模型：

```bash
ANTHROPIC_BASE_URL=https://your-proxy-endpoint   # 代理地址
ANTHROPIC_API_KEY=your-proxy-token                 # 代理认证 token
CLAUDE_MODEL=your-main-model                       # 主模型名称
CLAUDE_LIGHT_MODEL=your-light-model                # 轻量模型（用于验证/分类）
```

**完整示例（使用 GLM-5 代理）**：

```bash
# backend/.env
ANTHROPIC_API_KEY=your-proxy-token
ANTHROPIC_BASE_URL=https://llmapi.horizon.auto
CLAUDE_MODEL=GLM-5
SMARTPERFETTO_OUTPUT_LANGUAGE=zh-CN
```

**重要提示**：
- 代理必须支持 **Anthropic Messages API 格式**（不是 OpenAI 格式）
- 代理必须支持 **流式输出** 和 **tool/function calling**
- 常用代理：[one-api](https://github.com/songquanpeng/one-api)、[new-api](https://github.com/Calcium-Ion/new-api)、[LiteLLM](https://github.com/BerriAI/litellm)
- 如果代理只映射了一个模型，把 `CLAUDE_LIGHT_MODEL` 设为与 `CLAUDE_MODEL` 相同的值

### 3.4 慢模型超时配置

非 Anthropic 模型（DeepSeek/Ollama/GLM/Qwen）通常需要更长的超时时间：

```bash
CLAUDE_FULL_PER_TURN_MS=60000       # 完整分析每轮超时（默认 60s）
CLAUDE_QUICK_PER_TURN_MS=40000      # 快速分析每轮超时（默认 40s）
CLAUDE_VERIFIER_TIMEOUT_MS=60000    # 验证器单轮超时（默认 60s）
CLAUDE_CLASSIFIER_TIMEOUT_MS=30000  # 分类器超时（默认 30s）
```

---

## 4. 问题与解决方案

### 4.1 trace_processor_shell 下载失败（Google LUCI 不可达）

**现象**：`./start.sh` 在下载 `trace_processor_shell` 时卡住或超时，错误涉及 `commondatastorage.googleapis.com`。

**原因**：Google LUCI artifact server 从国内或部分 WSL2 环境无法直接访问。`start.sh` 和 `start-dev.sh` 默认从 Google 服务器下载固定版本的 `trace_processor_shell` 二进制。

**解决方案**：

**方案 A：手动下载（推荐）**

```bash
# 1. 使用可访问的网络下载二进制
wget https://commondatastorage.googleapis.com/perfetto-luci-artifacts/v54.0/linux-amd64/trace_processor_shell

# 2. 放置到指定目录
mkdir -p perfetto/out/ui/
mv trace_processor_shell perfetto/out/ui/trace_processor_shell
chmod +x perfetto/out/ui/trace_processor_shell

# 3. 验证
./perfetto/out/ui/trace_processor_shell --version
```

**方案 B：使用已有 binary 环境变量**

```bash
TRACE_PROCESSOR_PATH=/absolute/path/to/trace_processor_shell ./start.sh
```

**方案 C：使用镜像**

```bash
# 使用保持相同目录结构的可信镜像
TRACE_PROCESSOR_DOWNLOAD_BASE=https://your-mirror/perfetto-luci-artifacts ./start.sh

# 或使用当前平台的精确 binary URL
TRACE_PROCESSOR_DOWNLOAD_URL=https://your-mirror/trace_processor_shell ./start.sh
```

**方案 D：Docker 运行（免下载）**

```bash
docker compose -f docker-compose.hub.yml pull
docker compose -f docker-compose.hub.yml up -d
```

Docker 镜像内已包含固定版本的 `trace_processor_shell`。

**版本说明**：下载版本由 `scripts/trace-processor-pin.env` 固定。升级 perfetto submodule 时需同步更新此文件中的版本号和 SHA256 校验值。

---

### 4.2 文件上传大小限制 (MulterError: LIMIT_FILE_SIZE)

**现象**：上传较大的 trace 文件时，后端返回 500 错误，日志显示：

```
MulterError: File too large
  code: 'LIMIT_FILE_SIZE'
```

**原因**：`backend/src/routes/simpleTraceRoutes.ts` 中的 `multer` 中间件有文件大小限制。旧版本代码中该限制被硬编码为 500MB：

```typescript
// 旧代码 — 硬编码 500MB
const MAX_UPLOAD_BYTES = 500 * 1024 * 1024;
```

而 `MAX_FILE_SIZE` 环境变量默认值为 2GB（`2147483648`），两者不一致导致即使环境变量设对了，实际上传仍被 500MB 限制拦截。

**解决方案**：已在代码中修复，改为读取环境变量：

```typescript
// 新代码 — 读取环境变量，默认 2GB
const MAX_UPLOAD_BYTES = parseInt(process.env.MAX_FILE_SIZE || '2147483648');
```

**验证**：在 `backend/.env` 中设置 `MAX_FILE_SIZE=2147483648`（2GB），重启后端后上传大文件。

---

### 4.3 Claude Agent SDK musl 二进制兼容性问题（WSL2/glibc）

**现象**：AI 分析启动后立即失败，错误信息：

```
Claude Code native binary not found at
  .../node_modules/@anthropic-ai/claude-agent-sdk-linux-x64-musl/claude.
Please ensure Claude Code is installed via native installer
or specify a valid path
```

**原因**：

Claude Agent SDK 在 Linux 平台上有两个二进制变体：

| 变体 | npm 包 | 动态链接器 | 适用系统 |
|------|--------|-----------|---------|
| musl | `claude-agent-sdk-linux-x64-musl` | `/lib/ld-musl-x86_64.so.1` | Alpine Linux 等 musl 系统 |
| glibc | `claude-agent-sdk-linux-x64` | `/lib64/ld-linux-x86-64.so.2` | Ubuntu/Debian/CentOS 等 glibc 系统 |

**SDK 的二进制发现逻辑**在 Linux 上优先选择 musl 变体（`linux-x64-musl`），然后才 fallback 到 glibc 变体（`linux-x64`）。问题是：在 glibc 系统（如 WSL2 Ubuntu）上，musl 二进制文件虽然存在于 `node_modules` 中，但无法执行——因为系统缺少 musl 动态链接器 `/lib/ld-musl-x86_64.so.1`。

当 SDK 尝试执行 musl 二进制时，Linux 内核返回 `ENOENT`（找不到动态链接器），shell 报 `not found`，SDK 将此解读为 "binary not found" 而不是 "binary incompatible"，导致错误信息具有误导性。

**验证方法**：

```bash
# 检查系统是否为 glibc
ls /lib64/ld-linux-x86-64.so.2  # 存在 = glibc 系统

# 测试 musl 二进制（在 glibc 系统上会失败）
./node_modules/@anthropic-ai/claude-agent-sdk-linux-x64-musl/claude --version
# 输出: not found（实际上是动态链接器缺失）

# 测试 glibc 二进制（正常工作）
./node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude --version
# 输出: 2.1.132 (Claude Code)
```

**解决方案**：

已在 `backend/src/agentv3/claudeConfig.ts` 中添加了 `resolveClaudeCodeBinaryPath()` 函数，该函数：

1. 优先检查 `CLAUDE_CODE_BINARY_PATH` 环境变量（用户手动指定）
2. 在 Linux 上检测 `/lib64/ld-linux-x86-64.so.2` 是否存在（判断是否为 glibc 系统）
3. 如果是 glibc 系统，解析并返回 glibc 变体的路径

所有 7 个 `sdkQuery` 调用点已注入 `pathToClaudeCodeExecutable: resolveClaudeCodeBinaryPath()`：

| 文件 | 用途 |
|------|------|
| `claudeRuntime.ts` | 主编排器（通过 `sdkQueryWithRetry`） |
| `claudeVerifier.ts` | 结论验证器 |
| `queryComplexityClassifier.ts` | 查询复杂度分类 |
| `criticalPathAiSummary.ts` | 关键路径 AI 摘要 |
| `sceneStage3Summarizer.ts` | 场景摘要 |
| `flamegraphAiSummary.ts` | 火焰图 AI 摘要 |
| `reviewAgentSdk.ts` | 自改进审查代理 |

**手动覆盖**：如果自动检测有问题，可以设置环境变量：

```bash
# backend/.env
CLAUDE_CODE_BINARY_PATH=/absolute/path/to/claude-agent-sdk-linux-x64/claude
```

**适用环境**：此问题影响所有 glibc Linux 系统（Ubuntu/Debian/CentOS/WSL2），不影响 macOS 和 Windows。

---

### 4.4 前端服务被意外终止（restart-backend.sh 副作用）

**现象**：运行 `./scripts/restart-backend.sh` 后，前端服务也被关闭了。

**原因**：`start.sh` 在一个进程组中同时启动前端和后端。`restart-backend.sh` 会杀掉原始进程组，其中包括前端进程。

**解决方案**：

1. **只用 `./start.sh`**：正常启动和重启都通过 `start.sh`，它会自动处理进程清理
2. **后端热重载**：`tsx watch` 会检测 `.ts` 文件变更并自动重载，不需要手动重启后端
3. **手动重启前端**：如果前端被意外终止，单独启动：

```bash
node frontend/server.js
```

4. **仅 `.env` 变更需要手动重启**：后端的环境变量变更（`ANTHROPIC_API_KEY`、`CLAUDE_MODEL` 等）需要 `restart-backend.sh` 或手动重启后端进程

**什么时候用 restart-backend.sh**：
- 修改了 `backend/.env`
- 执行了 `npm install`
- `tsx watch` 卡住不响应

---

### 4.5 AI 后端未连接

**现象**：前端 AI Assistant 面板显示：

```
AI 后端未连接
无法连接到 AI 分析后端 (http://localhost:3000)
```

**排查步骤**：

1. **确认后端正在运行**：
   ```bash
   curl http://localhost:3000/health
   ```

2. **确认 AI 已配置**：health 响应中 `aiEngine.configured` 应为 `true`

3. **确认 `.env` 文件存在**：
   ```bash
   ls backend/.env
   ```

4. **确认 CORS 配置正确**：
   ```bash
   # backend/.env 中应有
   FRONTEND_URL=http://localhost:10000
   ```

5. **查看后端日志**：
   ```bash
   tail -50 logs/backend_latest.log
   ```

---

### 4.6 局域网访问配置

**现象**：其他设备（手机、另一台电脑）无法通过局域网 IP 访问 SmartPerfetto，或从 LAN IP 访问时 AI 助手无法连接后端。

**原因**：后端和前端的 `listen()` 不指定 hostname，Node.js 默认绑定 `0.0.0.0`（所有接口），所以服务本身局域网可达。但以下几个配置默认假设 `localhost` 访问，从其他机器用 LAN IP 访问时会被 CORS 或 CSP 拦截：

| 配置项 | 默认值 | 问题 |
|--------|--------|------|
| `FRONTEND_URL` | `http://localhost:10000` | CORS 检查拒绝非 localhost 来源 |
| `PERFETTO_UI_ORIGIN` | `http://localhost:10000` | trace_processor_shell CORS 拒绝 |
| `CORS_ORIGINS` | 仅含 localhost | 后端 CORS 中间件拒绝 |
| 前端 JS `getBackendUrl()` | `http://localhost:3000` | 浏览器尝试连 localhost 而非 LAN IP |
| CSP `connect-src` | 仅含 `localhost:3000` | 浏览器 CSP 阻止 fetch 到 LAN IP |

**额外原因（WSL2 环境）**：WSL2 运行在 Hyper-V 虚拟机内，拥有独立虚拟网卡 IP（如 `172.21.x.x`），与 Windows 宿主通过 NAT 隔离。局域网设备只能路由到 Windows 的真实网卡 IP（如 `<WINDOWS_LAN_IP>`），无法直接访问 WSL2 内部服务。需要在 Windows 侧设置端口转发。

```
外部设备 → Windows 网卡 (<WINDOWS_LAN_IP>:端口)
         → netsh portproxy 转发
         → WSL2 虚拟机 (<WSL_IP>:端口)
         → SmartPerfetto 服务
```

**解决方案**：

1. **获取网络地址**：
   ```bash
   # WSL2 内部 IP（服务实际运行位置）
   hostname -I | awk '{print $1}'
   # 例如: 172.21.237.238

   # Windows LAN IP（在 Windows PowerShell 中运行）
   ipconfig | findstr "IPv4"
   # 例如: 192.168.1.100
   ```

2. **修改 `backend/.env`**，添加/更新以下变量（使用 **Windows LAN IP**，不是 WSL2 内部 IP）：
   ```bash
   # 将 <WINDOWS_LAN_IP> 替换为 Windows 侧的局域网 IP
   FRONTEND_URL=http://<WINDOWS_LAN_IP>:10000
   PERFETTO_UI_ORIGIN=http://<WINDOWS_LAN_IP>:10000
   CORS_ORIGINS=http://localhost:8080,http://localhost:5173,http://localhost:5174,http://localhost:10000,http://127.0.0.1:8080,http://127.0.0.1:5173,http://127.0.0.1:5174,http://127.0.0.1:10000,http://<WINDOWS_LAN_IP>:10000
   ```

3. **前端 JS 动态 URL**（已修改）：`assistant-critical-path.js` 和 `assistant-flamegraph.js` 中的 `getBackendUrl()` fallback 已从 `http://localhost:3000` 改为 `location.protocol + '//' + location.hostname + ':3000'`，自动适配当前访问地址。

4. **CSP 白名单**（已修改）：`frontend_bundle.js` 的 `connect-src` 已加入 LAN IP。

5. **trace_processor_shell CORS**（已修改）：`workingTraceProcessor.ts` 已支持自动生成 localhost + LAN IP 双向 CORS origins。

6. **Windows 端口转发**（WSL2 环境必需）——在 **Windows PowerShell（管理员）** 中运行：
   ```powershell
   # 将 <WSL_IP> 替换为 WSL2 内部 IP（步骤 1 中获取的值）
   netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=<WSL_IP>
   netsh interface portproxy add v4tov4 listenport=10000 listenaddress=0.0.0.0 connectport=10000 connectaddress=<WSL_IP>

   # 放行 Windows 防火墙
   netsh advfirewall firewall add rule name="SmartPerfetto Backend" dir=in action=allow protocol=TCP localport=3000
   netsh advfirewall firewall add rule name="SmartPerfetto Frontend" dir=in action=allow protocol=TCP localport=10000

   # 验证
   netsh interface portproxy show all
   ```

7. **重启后端**（.env 变更需要重启）：
   ```bash
   ./scripts/restart-backend.sh
   ```

**验证**：

```bash
# 1. 通过 Windows LAN IP 检查后端
curl -s http://<WINDOWS_LAN_IP>:3000/health

# 2. 检查 CORS 头
curl -sI -H "Origin: http://<WINDOWS_LAN_IP>:10000" http://<WINDOWS_LAN_IP>:3000/health | grep -i access-control
# 预期: Access-Control-Allow-Origin: http://<WINDOWS_LAN_IP>:10000

# 3. 从其他设备浏览器打开
# http://<WINDOWS_LAN_IP>:10000
```

**注意**：
- WSL2 内部 IP 每次重启可能变化，端口转发规则需要同步更新。可以用 `netsh interface portproxy set v4tov4 ...` 更新，或先 `delete` 再 `add`
- Windows LAN IP 由 DHCP 分配，切换网络后也可能变化，需更新 `.env` 并重启后端
- 如果只需要本地访问，保持默认 `localhost` 配置即可，无需添加 LAN IP 和端口转发
- 删除端口转发规则：`netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0`

---

## 5. 配置速查表

### 完整 `backend/.env` 示例

```bash
# ===== 服务配置 =====
PORT=3000
NODE_ENV=development
FRONTEND_URL=http://localhost:10000

# ===== AI 模型配置 =====
# 方式1: Anthropic 直连
# ANTHROPIC_API_KEY=sk-ant-xxx

# 方式2: 第三方 LLM 代理
ANTHROPIC_API_KEY=your-proxy-token
ANTHROPIC_BASE_URL=https://your-proxy-endpoint
CLAUDE_MODEL=your-main-model
# CLAUDE_LIGHT_MODEL=your-light-model     # 可选，不设则用默认 haiku

# 方式3: Claude Code 本地认证（无需配置 .env）

# ===== 输出语言 =====
SMARTPERFETTO_OUTPUT_LANGUAGE=zh-CN       # zh-CN 或 en

# ===== 慢模型超时（非 Anthropic 模型建议调大）=====
# CLAUDE_FULL_PER_TURN_MS=60000
# CLAUDE_QUICK_PER_TURN_MS=40000
# CLAUDE_VERIFIER_TIMEOUT_MS=60000
# CLAUDE_CLASSIFIER_TIMEOUT_MS=30000

# ===== WSL2/glibc 二进制路径（通常自动检测，无需手动设置）=====
# CLAUDE_CODE_BINARY_PATH=/path/to/claude-agent-sdk-linux-x64/claude

# ===== 文件上传 =====
MAX_FILE_SIZE=2147483648                  # 2GB
UPLOAD_DIR=./uploads

# ===== 局域网访问（可选，仅 localhost 访问可跳过）=====
# PERFETTO_UI_ORIGIN=http://<LAN_IP>:10000   # trace_processor CORS origin
# CORS_ORIGINS=http://localhost:10000,...,http://<LAN_IP>:10000  # 后端 CORS 白名单

# ===== API 鉴权（可选）=====
# SMARTPERFETTO_API_KEY=your-strong-secret

# ===== 旧版 agentv2（已废弃）=====
# AI_SERVICE=deepseek
# DEEPSEEK_API_KEY=xxx
# DEEPSEEK_BASE_URL=https://api.deepseek.com
# DEEPSEEK_MODEL=deepseek-v4-flash
```

### 端口清单

| 服务 | 默认端口 | 说明 |
|------|---------|------|
| Backend API | 3000 | Express 后端 |
| Perfetto UI | 10000 | 前端界面 |
| trace_processor HTTP RPC | 9100-9900 | 端口池（自动分配） |

---

## 6. 验证清单

搭建完成后，按此清单逐一验证：

- [ ] **后端健康**：`curl http://localhost:3000/health` 返回 `{"status":"OK"}`
- [ ] **AI 已配置**：health 响应 `aiEngine.configured === true`
- [ ] **前端可访问**：浏览器打开 `http://localhost:10000` 看到 Perfetto UI
- [ ] **trace 上传正常**：上传一个 `.pftrace` 文件不报错
- [ ] **AI 分析可用**：在 AI Assistant 中输入简单问题（如 "应用包名是什么"）能得到回复
- [ ] **SDK 二进制正确**：AI 分析不报 "native binary not found" 错误

### 快速验证命令

```bash
# 1. 后端健康
curl -s http://localhost:3000/health | python3 -m json.tool

# 2. AI 配置状态
curl -s http://localhost:3000/health | python3 -c "
import sys, json
d = json.load(sys.stdin)
ai = d.get('aiEngine', {})
print(f'Configured: {ai.get(\"configured\")}')
print(f'Provider: {ai.get(\"providerMode\")}')
print(f'Model: {ai.get(\"model\")}')
"

# 3. TypeScript 编译检查
cd backend && npx tsc --noEmit
```
