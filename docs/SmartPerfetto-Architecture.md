# SmartPerfetto 项目架构全景

> AI 驱动的 Android 性能分析平台，基于 Perfetto trace 数据进行深度性能诊断。

---

## 1. 项目概览

| 维度 | 说明 |
|------|------|
| **定位** | AI 驱动的 Perfetto trace 分析平台 |
| **语言** | TypeScript (strict), Rust (火焰图分析器) |
| **运行时** | Node.js 24 LTS |
| **前端** | Forked Perfetto UI (Mithril.js) |
| **后端** | Express 5 + Claude Agent SDK |
| **AI 引擎** | Anthropic Claude (主), OpenAI/DeepSeek/Kimi/Qwen/GLM/Ollama 等 (通过代理) |
| **协议** | HTTP REST + SSE 实时流 |
| **部署** | Docker (多阶段构建), Docker Hub (`w553000664/smartperfetto`) |
| **License** | AGPL-3.0-or-later |

---

## 2. 顶层目录结构

```
SmartPerfetto/
├── backend/                    # 后端 — Express + AI Agent 运行时
│   ├── src/                    # TypeScript 源码
│   │   ├── agent/              # Legacy Agent 框架 (v1)
│   │   ├── agentv2/            # Agent v2 (已弃用, AI_SERVICE=deepseek 激活)
│   │   ├── agentv3/            # Agent v3 (主运行时, Claude Agent SDK)
│   │   ├── assistant/          # 会话管理 & SSE 流
│   │   ├── cli-user/           # CLI 接口
│   │   ├── config/             # 阈值 & 配置
│   │   ├── routes/             # Express 路由
│   │   ├── services/           # 业务逻辑层 (60+ 服务)
│   │   ├── types/              # TypeScript 类型定义
│   │   └── utils/              # 工具函数
│   ├── skills/                 # YAML 技能定义 (160+ 文件)
│   ├── strategies/             # 分析策略 & 提示词模板 (41 文件)
│   ├── sql/                    # SmartPerfetto PerfettoSQL 包
│   ├── tests/                  # 集成/e2e/skill-eval/agent-eval 测试
│   └── data/                   # SQL 索引, stdlib 符号
├── frontend/                   # 预构建 Perfetto UI (静态文件)
│   ├── server.js               # 前端 HTTP 服务器 (:10000)
│   └── v54.0-*/                # 版本化构建产物 (JS/WASM/CSS/字体)
├── perfetto/                   # Git submodule (Fork, 非直接编辑)
├── rust/                       # Rust 火焰图分析器
│   └── flamegraph-analyzer/    # Cargo 项目
├── scripts/                    # 运维脚本 (10+ 个)
├── test-traces/                # 6 个标准测试 trace (67MB)
├── docs/                       # 项目文档
├── Dockerfile                  # 4 阶段多架构构建
├── docker-compose.yml          # 源码构建编排
├── docker-compose.hub.yml      # Docker Hub 镜像编排
└── package.json                # Workspace 根配置
```

---

## 3. 系统架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                     用户浏览器                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              Perfetto UI Plugin (Mithril.js)                 │  │
│  │  AIPanel ← SSE ← Backend  |  SqlResultTable  |  Charts     │  │
│  │  SceneNav  |  BookmarkBar  |  SettingsModal   |  Story      │  │
│  └──────────────────┬───────────────────────────────────────────┘  │
└─────────────────────┼──────────────────────────────────────────────┘
                      │ HTTP REST + SSE
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Backend (Express 5 @ :3000)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │
│  │ agentRoutes   │→│ SessionMgr   │→│ IOrchestrator.analyze() │  │
│  └──────────────┘  └──────────────┘  └────────┬────────────────┘  │
│                                                 │                   │
│              ┌──────────────────────────────────┤                   │
│              ▼                                  ▼                   │
│  ┌───────────────────┐            ┌──────────────────────┐         │
│  │  ClaudeRuntime v3 │            │  AgentRuntime v2 ⚠️   │         │
│  │  (Claude Agent SDK)│           │  (已弃用, DeepSeek)   │         │
│  └────────┬──────────┘            └──────────────────────┘         │
│           │                                                        │
│  ┌────────┼────────────────────────────────────────────┐          │
│  │        ▼              MCP Server (20 tools)         │          │
│  │  ┌────────────┐ ┌────────────┐ ┌──────────────────┐ │          │
│  │  │ execute_sql │ │invoke_skill│ │ detect_arch      │ │          │
│  │  └──────┬─────┘ └──────┬─────┘ └──────────────────┘ │          │
│  │         │              │                              │          │
│  │         ▼              ▼                              │          │
│  │  ┌──────────────┐ ┌──────────────────┐               │          │
│  │  │ trace_proc   │ │ SkillExecutor    │               │          │
│  │  │ (SQL 查询)   │ │ (YAML → SQL)     │               │          │
│  │  └──────────────┘ └──────────────────┘               │          │
│  └──────────────────────────────────────────────────────┘          │
│                                                                     │
│  ┌──────────────────────────────────────────────────────┐          │
│  │              Strategy & Prompt System                 │          │
│  │  sceneClassifier → strategy.md → buildSystemPrompt   │          │
│  │  4-tier caching: STATIC > PER-TRACE > PER-QUERY      │          │
│  │                    > PER-INTERACTION                  │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                      │
                      ▼ HTTP RPC (9100-9900)
┌─────────────────────────────────────────────────────────────────────┐
│          trace_processor_shell (SQLite, 共享实例)                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. 核心调用链

### 4.1 分析请求主流程

```
POST /api/agent/v1/analyze
  │
  ├─ 1. agentRoutes.ts:664 — 校验 traceId, query, selectionContext
  ├─ 2. TraceProcessorService.getOrLoadTrace() — 加载 trace
  ├─ 3. AgentAnalyzeSessionService.prepareSession() — 创建/恢复会话
  │     ├─ 新会话: 创建 AnalysisSession + IOrchestrator 实例
  │     └─ 已有会话: 恢复状态, 递增 turn 计数
  ├─ 4. runAgentDrivenAnalysis() — 异步启动分析 (HTTP 立即返回 sessionId)
  │     ├─ session.orchestrator.on('update', handleUpdate) — 订阅事件
  │     ├─ session.orchestrator.analyze(query, sessionId, traceId, options)
  │     └─ 完成后: 存储结果, 广播 analysis_completed
  └─ 5. 返回 {success, sessionId, isNewSession, observability}
```

### 4.2 Agent v3 (ClaudeRuntime) 分析流程

```
ClaudeRuntime.analyze()
  │
  ├─ 1. classifyScene(query) — 关键词场景分类 (12 场景)
  ├─ 2. detectFocusApps() — 检测焦点应用
  ├─ 3. classifyQueryComplexity() — 复杂度路由
  │     ├─ 快速路径 (quick): 3 MCP 工具, 10 轮, 低 effort
  │     └─ 完整路径 (full): 20 MCP 工具, 60 轮, 高 effort
  │
  ├─ [快速路径] analyzeQuick()
  │     ├─ buildQuickSystemPrompt() (~1500 tokens)
  │     ├─ 3 个轻量 MCP 工具: execute_sql, invoke_skill, lookup_sql_schema
  │     └─ 无验证/子 Agent
  │
  └─ [完整路径] prepareAnalysisContext() + SDK 管线
        ├─ architectureDetector — 检测渲染架构 (STANDARD/FLUTTER/COMPOSE/WEBVIEW)
        ├─ skillRegistry — 初始化技能注册表
        ├─ buildSystemPromptParts() — 4 层系统提示词组装
        │     Tier 1 STATIC: 角色, 语言, 输出格式
        │     Tier 2 PER-TRACE: 架构, 焦点应用, 知识库
        │     Tier 3 PER-QUERY: 场景策略, 方法论, 子 Agent 指导
        │     Tier 4 PER-INTERACTION: 选择上下文, 对话历史, 计划历史
        ├─ createClaudeMcpServer() — 创建 20 个 MCP 工具
        ├─ sdkQueryWithRetry() — 指数退避重试
        ├─ createSseBridge() — SDK 消息 → SSE 事件翻译
        ├─ verifyConclusion() — 4 层验证 (启发式 + 计划 + 假设 + LLM)
        └─ 自我改进: 模式记忆, SQL 错误修复学习, 负面模式记录
```

### 4.3 SSE 事件流

```
ClaudeRuntime.emit('update')
  → agentRoutes.handleUpdate()
    → StreamProjector → SSE response → 浏览器
    → DataEnvelope → 场景重建 TrackEvents
    → ConversationStep → 时间线层
```

| SSE 事件 | 说明 |
|----------|------|
| `progress` | 阶段转换 (starting/analyzing/concluding) |
| `agent_response` | MCP 工具结果 (SQL/Skill) |
| `answer_token` | 最终文本流式输出 |
| `thought` | 中间推理过程 |
| `conclusion` | SDK 结果到达, 结论就绪 |
| `analysis_completed` | 终态 — HTML 报告生成完毕 |
| `error` | 异常 |

### 4.4 技能执行流程

```
MCP invoke_skill(skillId, params)
  │
  ├─ SkillRegistry.findMatchingSkill() — 查找技能
  ├─ SkillExecutor.executeCompositeSkill() / executeAtomicSkill()
  │     │
  │     ├─ SkillExecutor.executeStep() — 步骤分发
  │     │     ├─ atomic → executeAtomicStep() — 单条 SQL
  │     │     ├─ iterator → executeIteratorStep() — 循环遍历数据
  │     │     ├─ parallel → executeParallelStep() — Promise.all 并行
  │     │     ├─ diagnostic → executeDiagnosticStep() — 规则推理
  │     │     ├─ conditional → executeConditionalStep() — 条件分支
  │     │     ├─ pipeline → executePipelineStep() — 渲染管线教学
  │     │     ├─ ai_decision → executeAIDecisionStep() — AI 判断
  │     │     └─ ai_summary → executeAISummaryStep() — AI 摘要
  │     │
  │     ├─ ExpressionEvaluator — 变量替换 & JS 表达式求值
  │     ├─ organizeByLayer() — L1→L2→L3→L4 分层结果
  │     └─ substituteVariables() — SQL 模板变量替换
  │
  └─ LayeredResult → DataEnvelope → SSE → 前端渲染
```

---

## 5. 模块依赖关系

### 5.1 后端核心依赖图

```
agentRoutes.ts
  ├── AgentAnalyzeSessionService (会话准备)
  │     ├── AssistantApplicationService (会话生命周期, SSE 管理)
  │     ├── SessionPersistenceService (会话持久化)
  │     └── ModelRouter (LLM 路由)
  │
  └── runAgentDrivenAnalysis()
        └── IOrchestrator.analyze()
              │
              ├── [v3] ClaudeRuntime
              │     ├── sceneClassifier (关键词场景分类)
              │     ├── queryComplexityClassifier (快速/完整路由)
              │     ├── focusAppDetector (焦点应用检测)
              │     ├── architectureDetector (渲染架构检测)
              │     ├── claudeSystemPrompt (4 层提示词组装)
              │     │     └── strategyLoader (策略 & 模板加载)
              │     ├── claudeMcpServer (MCP 工具定义)
              │     │     ├── execute_sql → TraceProcessorService
              │     │     ├── invoke_skill → SkillExecutor → SkillRegistry
              │     │     ├── detect_architecture → ArchitectureDetector
              │     │     ├── lookup_sql_schema → SqlKnowledgeBase
              │     │     ├── write_analysis_note → session notes
              │     │     ├── fetch_artifact → ArtifactStore
              │     │     ├── list_stdlib_modules → PerfettoStdlibIndex
              │     │     └── lookup_knowledge → Knowledge 模板
              │     ├── claudeSseBridge (SDK 消息 → StreamingUpdate)
              │     ├── claudeVerifier (4 层验证)
              │     ├── analysisPatternMemory (模式记忆)
              │     └── sqlErrorFixLearning (SQL 错误修复学习)
              │
              └── [v2] AgentRuntime (已弃用)
                    ├── OperationPlanner, PrincipleEngine
                    ├── OperationExecutor, EvidenceSynthesizer
                    └── RuntimeGovernancePipeline
```

### 5.2 前端组件依赖图

```
Plugin Index (index.ts)
  ├── AIPanel (主面板, 50+ 状态字段)
  │     ├── AIService / Assistant API v1 (后端通信)
  │     ├── SessionManager (localStorage 持久化)
  │     ├── StreamingFlowState (流式状态机)
  │     ├── StreamingAnswerState (答案流式状态)
  │     ├── StoryController (场景重建, 独立 SSE)
  │     ├── ComparisonStateManager (双 trace 对比)
  │     ├── CommandBus (跨组件通信)
  │     └── SettingsModal (设置面板)
  │
  ├── SqlResultTable (数据表格, schema 驱动)
  │     ├── ChartVisualizer (纯 SVG 图表: 饼图/柱状图/直方图)
  │     ├── ColumnDefinition (类型推断 & 格式化)
  │     └── Formatters (数值/百分比/时长/字节格式化)
  │
  ├── MermaidRenderer (懒加载, Base64 编码, CSP 合规)
  ├── NavigationBookmarkBar (书签导航: jank/anr/slow/binder/custom)
  ├── SceneNavigationBar (场景导航: 启动/滑动/ANR/卡顿 等)
  ├── InterventionPanel (6 种干预类型)
  ├── ProviderQuickSwitcher (AI 提供者快速切换)
  └── FloatingWindow (浮动窗口/侧边栏/标签页 三种模式)
```

### 5.3 关键 NPM 依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `@anthropic-ai/claude-agent-sdk` | ^0.2.132 | Claude Agent SDK — Agent v3 核心 |
| `express` | ^5.2.1 | HTTP 服务器框架 |
| `openai` | ^6.36.0 | OpenAI 兼容 API 客户端 (多提供者代理) |
| `better-sqlite3` | ^12.9.0 | SQLite 驱动 (trace 数据查询) |
| `zod` | ^4.4.3 | 运行时类型校验 |
| `multer` | - | 文件上传 (trace 上传) |
| `commander` | - | CLI 命令框架 |
| `axios` | - | HTTP 客户端 |
| `markdown-it` | - | Markdown 渲染 |

---

## 6. 技术栈详解

### 6.1 后端技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **运行时** | Node.js 24 LTS | engine-strict 模式 |
| **语言** | TypeScript 5.9 (strict) | ES2020 target, commonjs |
| **框架** | Express 5.2 | HTTP + SSE |
| **AI SDK** | Claude Agent SDK 0.2 | Agent v3 编排器 |
| **LLM 客户端** | OpenAI SDK 6.x | 兼容多提供者代理 |
| **数据库** | better-sqlite3 | trace_processor Shell 交互 |
| **类型校验** | Zod 4.4 | 运行时 schema 验证 |
| **构建** | tsc + copy-runtime-assets | 后端构建管线 |
| **开发** | tsx watch | 热重载 |
| **测试** | Jest 30 + ts-jest | 单元/集成/e2e |
| **Lint** | Biome 2.4 | 格式化 + lint |
| **死代码** | Knip 6.12 | 未使用代码检测 |
| **CLI** | Commander | smp/smartperfetto 命令行 |

### 6.2 前端技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **框架** | Perfetto UI (Fork) | Google 官方 Perfetto 修改版 |
| **UI 库** | Mithril.js | 轻量级组件框架 |
| **图表** | 纯 SVG | 饼图/柱状图/直方图 (无外部依赖) |
| **流程图** | Mermaid.js | 懒加载, 本地 CSP 合规 |
| **样式** | 内联 JS 对象 / SCSS | 编译时打包 |
| **构建** | Perfetto build.js | pnpm, WASM (memory64) |
| **服务端** | Express (server.js) | 静态文件 + CORS + COOP/COEP |

### 6.3 Rust 组件

| 组件 | 说明 |
|------|------|
| `flamegraph-analyzer` | 火焰图分析器, Cargo 构建, Docker 多阶段编译 |

### 6.4 基础设施

| 组件 | 技术 | 说明 |
|------|------|------|
| **容器** | Docker (4 阶段构建) | backend-builder → flamegraph-builder → tp-downloader → runtime |
| **CI** | GitHub Actions | quality + gate + docker-smoke + publish |
| **镜像** | Docker Hub | `w553000664/smartperfetto:latest` |
| **版本固定** | trace-processor-pin.env | 4 平台 SHA256 校验 |

---

## 7. 关键特性

### 7.1 双路径 Agent 架构

| 特性 | 快速路径 (fast) | 完整路径 (full) |
|------|:---:|:---:|
| 轮次预算 | 10 | 60 |
| MCP 工具 | 3 个 (轻量) | 20 个 (完整) |
| 验证器 | 无 | 4 层 (启发式+计划+假设+LLM) |
| 子 Agent | 无 | frame/system/startup 专家 |
| 典型成本 | $0.05–0.25 | $0.3–1.0 |
| 延迟目标 | 3–8 秒 | 30–120 秒 |

**自动路由 (auto)**: `关键词预过滤 → 确定性硬规则 (7 场景) → Haiku 回退`

### 7.2 12 场景分类体系

| 优先级 | 场景 | 关键词示例 |
|:---:|------|------|
| 1 | ANR | anr, 无响应, 卡死 |
| 2 | 启动 (startup) | 启动, startup, 冷启动 |
| 3 | 滑动 (scrolling) | 滑动, scroll, 卡顿 |
| 4 | 交互 (interaction) | 点击, touch, 响应 |
| 5 | 触控追踪 (touch-tracking) | 触控, touch event |
| 6 | 教学 (teaching) | 渲染管线, pipeline, 教学 |
| 7 | 记忆 (memory) | 内存, memory, OOM |
| 8 | 游戏 (game) | 游戏, game, FPS |
| 9 | 总览 (overview) | 概览, overview |
| 10 | 滑动响应 (scroll-response) | 滑动响应 |
| 11 | 管线 (pipeline) | 渲染, render, VSYNC |
| 12 | 通用 (general) | (默认回退) |

### 7.3 YAML 技能系统 (160+ 文件)

| 目录 | 数量 | 说明 |
|------|:---:|------|
| `skills/atomic/` | 126 | 单步检测技能 (单条 SQL) |
| `skills/composite/` | 33 | 组合分析技能 (多步骤) |
| `skills/deep/` | 2 | 深度分析技能 |
| `skills/pipelines/` | 33 | 渲染管线检测 & 教学 |
| `skills/modules/` | 4 子目录 | 模块专家 (app/framework/hardware/kernel) |
| `skills/vendors/` | 8 厂商 | 厂商特定覆盖 (pixel/samsung/xiaomi/honor/oppo/vivo/qualcomm/mtk) |
| `skills/config/` | - | 结论场景模板 |

**9 种步骤类型**: `atomic`, `skill` (引用), `iterator`, `parallel`, `diagnostic`, `ai_decision`, `ai_summary`, `conditional`, `pipeline`

**4 层结果 (L1–L4)**:
- **L1 (overview)**: 聚合指标 — FPS, jank 率
- **L2 (list)**: 数据列表 — session/事件列表
- **L3 (diagnosis)**: 逐帧诊断 — iterator 遍历 jank 帧
- **L4 (deep)**: 深度分析 — 帧/调用级详情

### 7.4 策略 & 提示词系统 (41 文件)

| 类型 | 文件模式 | 说明 |
|------|---------|------|
| 场景策略 | `*.strategy.md` | YAML frontmatter (keywords, phase_hints, plan_template) + Markdown 分析指导 |
| 提示词模板 | `prompt-*.template.md` | 角色/方法论/输出格式/语言/快速分析/复杂度分类 |
| 知识模板 | `knowledge-*.template.md` | 6 个领域: binder-ipc, cpu-scheduler, rendering-pipeline, gc-dynamics, thermal-throttling, lock-contention |
| 架构模板 | `arch-*.template.md` | 4 种: standard, compose, flutter, webview |
| 选择模板 | `selection-*.template.md` | 区域选择 / slice 事件选择 |
| 对比模板 | `comparison-methodology.template.md` | 双 trace 对比方法论 |

**4 层提示词缓存**:

| 层级 | 范围 | 稳定性 | 内容 |
|:---:|------|--------|------|
| 1 | STATIC | 进程内不变 | 角色, 语言, 输出格式 |
| 2 | PER-TRACE | 单 trace 稳定 | 架构, 焦点应用, 知识库 |
| 3 | PER-QUERY | 同场景稳定 | 场景策略, 方法论, 子 Agent 指导 |
| 4 | PER-INTERACTION | 每次查询变 | 选择上下文, 对话历史, 计划历史 |

> Token 预算 4500, 超出时按 Tier 4→3 优先级裁剪, Tier 4 选择上下文永不裁剪。

### 7.5 DataEnvelope 统一数据契约 (v2.0)

```typescript
interface DataEnvelope<T> {
  meta: { type, version, source, skillId?, stepId? };
  data: T;  // { columns, rows, expandableData }
  display: { layer, format, title, columns?: ColumnDefinition[] };
}
```

- **语义列类型**: `timestamp`, `duration`, `number`, `string`, `percentage`, `bytes`, `boolean`, `enum`, `json`, `link`
- **点击动作**: `navigate_timeline`, `navigate_range`, `copy`, `expand`, `filter`, `link`
- **前后端 + HTML 报告** 三端共用

### 7.6 厂商覆盖系统

8 个 Android 厂商的特定检测和诊断覆盖:

```
vendors/qualcomm/    → Adreno GPU, Snapdragon 平台事件
vendors/mtk/         → MediaTek 平台事件
vendors/samsung/     → Samsung 特定调度器
vendors/xiaomi/      → MIUI 系统优化
vendors/pixel/       → Google Pixel 原生
vendors/honor/       → Honor 系统特征
vendors/oppo/        → ColorOS 特征
vendors/vivo/        → FuntouchOS 特征
```

运行时通过 SQL 查询 trace 自动检测厂商, 注入对应覆盖步骤和诊断规则。

### 7.7 自我改进机制

| 机制 | 说明 |
|------|------|
| **SQL 错误修复学习** | 60s 内捕获失败 SQL 和后续修复, Jaccard 相似度 >30% 匹配, 持久化到 `logs/sql_learning/` |
| **分析模式记忆** | 成功模式保存为 `provisional`, 24h 后自动确认; 快速路径模式可被完整路径验证提升 |
| **负面模式记录** | 记录失败策略 (strategy_failure, sql_error, verification_failure) |
| **技能笔记注入** | 按技能注入指导笔记, 预算允许时附加到工具响应 |
| **上下文压缩恢复** | SDK 自动 compact 后写入恢复笔记, 保留计划进度和发现 |

### 7.8 弹性 & 容错

| 机制 | 说明 |
|------|------|
| **Watchdog** | 连续 3 次工具失败 → 注入策略切换指令 |
| **Circuit Breaker** | 近期失败率 >60% → 简化分析范围 |
| **SDK 重试** | `sdkQueryWithRetry()` 指数退避 |
| **部分结果** | 错误/最大轮次耗尽时保留部分发现, 置信度扣减 |
| **EPIPE 防护** | SSE 客户端断开时防止进程崩溃 |
| **子 Agent 超时** | 独立超时管理, 不影响主 Agent |
| **上下文压力检测** | 预压缩处理 + 恢复笔记 |

### 7.9 多提供者支持

支持 15+ LLM 提供者, 三种连接模式:

| 模式 | 说明 |
|------|------|
| Anthropic 直连 | `ANTHROPIC_API_KEY` + 可选 `CLAUDE_MODEL` |
| AWS Bedrock | `CLAUDE_AWS_ACCESS_KEY` + Region 配置 |
| 第三方代理 | `ANTHROPIC_BASE_URL` 指向 one-api/new-api/LiteLLM 等代理 |

兼容提供者: GLM/Z.ai, DeepSeek, Qwen, Kimi, Doubao, MiniMax, 小米 MiMo, Baichuan, Yi, Spark, Hunyuan, OpenAI, Google Gemini, Ollama

### 7.10 场景重建 (Scene Reconstruction)

独立的 SSE 连接到 `/api/agent/v1/scene-reconstruct`, 实现场景级别的故事化分析:
- 自动检测场景 (冷启动/滑动/ANR 等)
- 逐场景生成分析报告
- 自动 Pin 相关 Track
- 支持 Deep Dive 下钻

---

## 8. API 端点汇总

### Agent (主路径)

| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/agent/v1/analyze` | 启动分析 |
| GET | `/api/agent/v1/:sessionId/stream` | SSE 实时流 |
| GET | `/api/agent/v1/:sessionId/status` | 轮询状态 |
| POST | `/api/agent/v1/resume` | 恢复分析 (多轮) |
| GET | `/api/agent/v1/:sessionId/turns` | 获取分析轮次 |
| POST | `/api/agent/v1/:sessionId/respond` | 多轮响应 |
| POST | `/api/agent/v1/:sessionId/intervene` | 用户干预 |
| POST | `/api/agent/v1/:sessionId/cancel` | 取消分析 |
| GET | `/api/agent/v1/:sessionId/focus` | 获取焦点应用 |
| GET | `/api/agent/v1/:sessionId/report` | 获取分析报告 |

### 场景重建

| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/agent/v1/scene-reconstruct` | 启动重建 |
| GET | `/api/agent/v1/scene-reconstruct/:id/stream` | SSE 流 |
| GET | `/api/agent/v1/scene-reconstruct/:id/status` | 状态 |
| POST | `/api/agent/v1/scene-reconstruct/:id/deep-dive` | 深入分析 |
| DELETE | `/api/agent/v1/scene-reconstruct/:id` | 删除 |

### 辅助

| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/agent/v1/scene-detect-quick` | 快速场景检测 |
| GET | `/api/agent/v1/teaching/pipeline` | 管线教学 |
| GET | `/api/traces/upload` | 上传 trace |
| POST | `/api/traces/register-rpc` | 注册 RPC trace |
| GET | `/api/skills/*` | 查询技能 |
| GET | `/api/reports/:id` | HTML 报告 |

---

## 9. 会话管理

| 维度 | 说明 |
|------|------|
| **存储** | 内存 `Map<sessionId, AnalysisSession>` |
| **清理** | 终态会话 30 分钟过期, 非终态 2 小时 |
| **SSE 重连** | 环形缓冲区 200 事件, `Last-Event-ID` 回放 |
| **持久化** | `SessionPersistenceService` 跨重启恢复 |
| **SDK 映射** | `logs/claude_session_map.json` (24h TTL, 防抖写入) |
| **容量限制** | 1200 dataEnvelope / 800 agentDialogue / 400 agentResponse |

---

## 10. MCP 工具清单 (Agent v3)

| 工具 | 类型 | 说明 |
|------|:---:|------|
| `execute_sql` | 始终 | SQL 查询, 计划门控, 行限制, 摘要模式 |
| `invoke_skill` | 始终 | 执行技能管线, 返回 artifact 引用或完整结果 |
| `list_skills` | 始终 | 列出可用分析技能 |
| `detect_architecture` | 始终 | 检测渲染架构 |
| `lookup_sql_schema` | 始终 | 搜索 Perfetto SQL stdlib 索引 |
| `write_analysis_note` | 始终 | 持久化结构化笔记 (20 条上限, 优先级淘汰) |
| `fetch_artifact` | 始终 | 分页获取存储的 artifact (summary/rows/full) |
| `list_stdlib_modules` | 始终 | 列出 Perfetto SQL stdlib 模块 |
| `lookup_knowledge` | 始终 | 加载领域知识 (6 个知识模板) |
| `lookup_blog_knowledge` | 条件 | 检索 androidperformance.com 索引块 |
| 其余 10 个 | 条件 | 完整路径专用: 对比, ADB, 场景检测, 子 Agent 等 |

---

## 11. 测试体系

### 11.1 测试层级

| 层级 | 命令 | 说明 |
|------|------|------|
| 类型检查 | `npm run typecheck` | tsc --noEmit |
| 单元测试 | `npm test -- --testPathPatterns="__tests__"` | ~2 min |
| 核心+回归 | `npm run test:scene-trace-regression` | 6 条 canonical trace |
| 技能评估 | `npm run test:skill-eval` | 需要 trace fixture |
| Agent 评估 | `npm run test:agent-eval` | 完整 Agent 评估 |
| PR 门禁 | `npm run verify:pr` | quality + typecheck + build + test:core + regression |
| E2E SSE | `verifyAgentSseScrolling.ts` | 完整 Agent SSE 验证 |

### 11.2 6 条标准测试 Trace

| 场景 | 文件 | 大小 |
|------|------|------|
| 重度启动 | `lacunh_heavy.pftrace` | 18.3 MB |
| 轻度启动 | `launch_light.pftrace` | 10.5 MB |
| 标准滑动 | `scroll_Standard-AOSP-App-Without-PreAnimation.pftrace` | 6.3 MB |
| 客户端滑动 | `scroll-demo-customer-scroll.pftrace` | 14.2 MB |
| Flutter TextureView | `Scroll-Flutter-327-TextureView.pftrace` | 7.0 MB |
| Flutter SurfaceView | `Scroll-Flutter-SurfaceView-Wechat-Wenyiwen.pftrace` | 12.0 MB |

---

## 12. 开发工作流

### 12.1 启动方式

| 用途 | 命令 | 说明 |
|------|------|------|
| 用户启动 | `./start.sh` | 预构建前端, 无需 submodule |
| UI 开发 | `./scripts/start-dev.sh` | 需要 submodule, 热重载 |
| 仅重启后端 | `./scripts/restart-backend.sh` | .env/npm 变更时 |
| 更新前端 | `./scripts/update-frontend.sh` | 修改 AI 插件 UI 后 |

### 12.2 变更后验证

| 变更类型 | 验证命令 |
|---------|---------|
| 后端 .ts/.yaml/.md | 刷新浏览器即可 (tsx watch 自动重载) |
| 前端插件 UI | `start-dev.sh` 热重载 → `update-frontend.sh` 更新 |
| MCP/内存/报告 | `cd backend && npm run test:scene-trace-regression` |
| 技能 YAML | `npm run validate:skills` + 回归测试 |
| 策略 .md | `npm run validate:strategies` + 回归测试 |
| PR 提交前 | `npm run verify:pr` |

---

## 13. CI/CD 管线

| 工作流 | 触发 | 说明 |
|--------|------|------|
| `backend-agent-regression-gate` | PR/Push to main | quality + gate (verify:pr) + docker-smoke |
| `docker-publish` | Tag (`v*.*.*`) / 每日 / 手动 | 多架构 Docker 构建推送 Docker Hub |
| `sync-upstream` | 每日 02:00 UTC | 同步上游 Gracker/SmartPerfetto fork |

---

## 14. 关键接口定义

### IOrchestrator (编排器统一接口)

```typescript
interface IOrchestrator {
  on(event: 'update', listener: (update: StreamingUpdate) => void): this;
  analyze(query, sessionId, traceId, options?): Promise<AnalysisResult>;
  reset(): void;
  cleanupSession(sessionId: string): void;
  getFocusStore?(): FocusStore;
  getInterventionController?(): InterventionController;
  getSdkSessionId?(sessionId: string): string | undefined;
  takeSnapshot?(sessionId: string): SessionStateSnapshot;
  restoreFromSnapshot?(sessionId: string, snapshot: SessionStateSnapshot): void;
  // ... 更多方法
}
```

### AnalysisResult (分析结果)

```typescript
interface AnalysisResult {
  sessionId: string;
  success: boolean;
  findings: Finding[];
  hypotheses: Hypothesis[];
  conclusion: string;
  confidence: number;
  rounds: number;
  totalDurationMs: number;
  partial?: boolean;
  terminationReason?: string;
}
```

---

## 15. 环境变量参考

### 核心

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | 3000 | 后端端口 |
| `ANTHROPIC_API_KEY` | - | Anthropic API Key 或代理认证 |
| `ANTHROPIC_BASE_URL` | - | 第三方 LLM 代理 URL |
| `CLAUDE_MODEL` | claude-sonnet-4-6 | 主模型 |
| `CLAUDE_LIGHT_MODEL` | claude-haiku-4-5 | 轻量模型 (分类器/验证器) |
| `CLAUDE_MAX_TURNS` | 60 | 完整路径轮次上限 |
| `CLAUDE_QUICK_MAX_TURNS` | 10 | 快速路径轮次上限 |

### 超时 (适配慢速 LLM)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE_FULL_PER_TURN_MS` | 60000 | 完整路径每轮超时 |
| `CLAUDE_QUICK_PER_TURN_MS` | 40000 | 快速路径每轮超时 |
| `CLAUDE_VERIFIER_TIMEOUT_MS` | 60000 | 验证器 LLM 超时 |
| `CLAUDE_CLASSIFIER_TIMEOUT_MS` | 30000 | 复杂度分类器超时 |

### 安全

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SMARTPERFETTO_API_KEY` | - | Bearer token 认证 |
| `AGENT_SQL_MAX_ROWS` | 1000 | SQL 结果行数限制 |
| `SMARTPERFETTO_USAGE_MAX_REQUESTS` | 200 | 请求限流 |

---

> 文档生成时间: 2026-05-07 | 基于代码库实际结构梳理
