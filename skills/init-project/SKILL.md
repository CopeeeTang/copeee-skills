---
name: init-project
description: "Bootstrap a new project's Claude Code configuration end-to-end: CLAUDE.md + .claude/settings.json + .claude/commands/ + hooks + recommended plugins/skills + .gitignore. Beyond /init: signal-driven recommendations from project type (ML research / web app / CLI / library / data pipeline / infra), personal vs team vs public sharing modes, and dry-run preview before any file is written. TRIGGER when: user wants to bootstrap/initialize/configure a new project for Claude Code (greenfield repo, fresh setup, '配置一个新项目', 'bootstrap project', 'init project', 'set up Claude Code for this repo'); user mentions /init-project command; user asks 'how do I configure Claude Code for X kind of project'; user wants to refactor existing .claude/ setup based on project type. Also trigger when user describes a new ML/research project + asks what configuration is needed. DO NOT trigger for: editing existing CLAUDE.md to fix one rule (use claude-md-improver), code-level work, single skill creation (use skill-creator), MCP setup question (use claude-automation-recommender)."
---

# init-project — Bootstrap Claude Code 项目配置

## 角色定位

你是项目"装修工长"。`/init` 是地基（一份 CLAUDE.md），本 skill 决定整个 `.claude/` 长什么样：哪些 plugin 装、哪些 hook 必须自动跑、个人 vs 团队的边界画在哪、推荐什么 slash commands。

**核心原则**：
1. **信号驱动**：先扫码再提问，不问已能从代码得知的
2. **节制**：每类 artifact 推荐 1–2 条，反 kitchen-sink
3. **dry-run 优先**：所有文件先打印 preview，用户审过再落盘
4. **个人 vs 团队**：明确分层，个人偏好绝不污染 git

---

## 触发后的执行流程

### Phase 1 — 扫码（自动，0 提问）

并行跑这些探测，把结果做成"已识别"摘要：

| 探测 | 工具 | 推断 |
|------|------|------|
| `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` | Read | 主语言 + 包管理器 |
| `git config remote.origin.url` | Bash | 是否有远端、个人/组织 repo |
| 顶层 `README.md` 前 50 行 | Read | 项目意图、关键术语 |
| `.cursorrules` / `.windsurfrules` / `AGENTS.md` | Glob | 已有 agent 指令（合并参考）|
| `tests/` / `test_*.py` / `*.test.ts` | Glob | 是否有测试 framework |
| `Dockerfile` / `docker-compose.yml` | Read | 部署形态 |
| `import torch` / `import tensorflow` 出现 | Grep `*.py` | ML 项目信号 |
| `azure-storage-blob` / `boto3` / `google-cloud-storage` | Grep | cloud 依赖 |
| `next.config` / `vite.config` / `webpack.config` | Glob | Web app 信号 |
| `bin/` 含 shebang | Bash | CLI 工具信号 |

输出格式（给用户看）：

```
✓ 已识别
  - 语言: Python (pyproject.toml + ruff 配置)
  - 部署: 无 Dockerfile（本地开发）
  - 信号: import torch (ML), azure-storage-blob (Azure cloud)
  - 远端: github.com/CopeeeTang/<repo>.git (个人)
  - 测试: 无 tests/ 目录
  - 已有指令: 无 (greenfield .claude/ 配置)
```

如果检测到 `CLAUDE.md` 已存在 → 切换到 audit 模式（建议改用 `claude-md-improver` skill），本 skill 不覆盖已有文件。

### Phase 2 — 项目阶段 + 共享模式（2 题强制）

```
Q1: 项目阶段？
  [a] 全新（greenfield，没写过代码）
  [b] 已有代码，第一次配 Claude Code
  [c] 已有 CLAUDE.md，要做体检 → 转 claude-md-improver 退出

Q2: 谁会用这份配置？
  [a] 仅自己 → 生成 CLAUDE.local.md + 个人 .gitignore
  [b] 团队共享 → CLAUDE.md 入 git，分私有偏好层（CLAUDE.local.md）
  [c] 公开 OSS → 额外做 sanity check（路径/IP/secret 不得入 git）
```

### Phase 3 — 项目类型（多选）

```
Q3: 项目主要形态？（可叠加）
  ☐ Web app / 后端 API
  ☐ CLI 工具 / 库
  ☐ ML 研究 / 模型训练 / 评估
  ☐ Data pipeline / ETL
  ☐ Infra / IaC / DevOps
  ☐ Notebook / 探索分析
```

每勾选一项 → 加载 `references/profile-{type}.md`（当前 MVP 只覆盖 `ml-research` 和 `web-app`，其他类型用通用模板 + 信号增强）。

### Phase 4 — 关键 dimension（通用 4 题 + 类型特定 1–3 题）

**通用必问**：
1. **测试命令**（如何跑测试）→ 进 CLAUDE.md "HOW" 段 + 写 PostToolUse hook
2. **Lint/format 命令** → **不**进 CLAUDE.md，写 hook
3. **绝不能直调的 endpoint**（如内部代理 only）→ CLAUDE.md "⚠️ IMPORTANT" 段
4. **敏感目录**（`.env`、`secrets/`、`migrations/`）→ `permissions.deny` + PreToolUse 阻断

**ML 研究项目额外问**（参考 `references/profile-ml-research.md`）：
- 数据在哪？（local / Azure Blob / HF / S3）
- 计算资源？（A100 / 4090 / 集群 / CPU）
- 性能目标？（latency / throughput / accuracy）
- 实验结果归档结构？

**Web app 项目额外问**（参考 `references/profile-web-app.md`）：
- 前端框架？后端运行时？
- 浏览器测试需要 Playwright MCP 吗？
- 数据库？需要装 postgres/supabase MCP 吗？

---

## Phase 5 — Dry-run preview + 用户确认

把要生成的全部 artifact 用以下格式 dump 一遍，**不写文件**：

```
========== DRY-RUN: 5 files will be created ==========

[1/5] CLAUDE.md (62 lines)
---内容---

[2/5] .claude/settings.json (54 lines)
---内容---

[3/5] .claude/commands/run-smoke.md (12 lines)
---内容---

[4/5] .gitignore (append 5 lines)
---追加内容---

[5/5] CLAUDE.local.md (28 lines, 个人模式)
---内容---

========== END DRY-RUN ==========

Confirm? [y / 编辑哪个 / cancel]
```

用户可以：
- `y` → 全部落盘
- `edit 2` → 修改第 2 个文件后再 preview
- `skip 4` → 不生成第 4 个
- `cancel` → 全部放弃

---

## Phase 6 — 写文件 + 后续指引

落盘后输出"下一步建议"：

```
✓ 已生成 4 个文件（跳过了 .gitignore 因为不是 git repo）

下一步：
  1. 重启 Claude Code 让 .claude/settings.json 的 plugin/hook 生效
  2. 第一个建议命令：试一下 /run-smoke
  3. 第一次出错或 Claude 犯同样错误 2 次时 → 加进 CLAUDE.md
  4. 30 天后 review CLAUDE.md，问"删了它 Claude 会不会犯错"——不会就删
```

---

## Artifact 矩阵（按"必生成 / 条件生成"）

| Artifact | 何时生成 | 大小目标 |
|----------|----------|----------|
| `CLAUDE.md` | 总是 | < 80 行 |
| `CLAUDE.local.md` | 个人模式 + 有个人偏好 | < 30 行 |
| `.claude/settings.json` | 总是 | 50–80 行 |
| `.claude/settings.local.json` | 个人模式 | < 20 行 |
| `.gitignore` 追加块 | 是 git repo | +5 行 |
| `.mcp.json` | 有外部依赖（DB / 浏览器测试） | 按需 |
| `.claude/commands/*.md` | 1–2 条高频 workflow | 每个 < 10 行 |
| `.claude/agents/*.md` | 大项目（>10K LoC）才 | 每个 < 50 行 |
| `AGENTS.md` 软链 | 同时用 Codex / Cursor 才 | `ln -s CLAUDE.md AGENTS.md` |
| `SPEC.md` 模板 | 用户勾选"我要 spec-driven" | 50 行模板 |

---

## 反模式（必避免）

1. **Kitchen-sink**：每类 artifact 推荐 ≤ 2 条；类型表里的"建议清单"绝不是"全装"
2. **lint 写进 CLAUDE.md**：HumanLayer "Never send an LLM to do a linter's job"——能交给 hook 的事绝不写 prose
3. **个人偏好混进 team CLAUDE.md**：永远分 `CLAUDE.md`（git）vs `CLAUDE.local.md`（gitignore）
4. **盲生成不审**：所有写盘前必走 Phase 5 dry-run，用户能逐文件 edit/skip/cancel
5. **过早 over-engineering**：greenfield 不装 5 个 MCP + 4 个 subagent；先 CLAUDE.md + settings.json，后面按"出现真实痛点再加"
6. **复制别人的模板**：`references/profile-*.md` 是"起点"不是"答案"，必须基于 interview 答案裁剪
7. **slash command 满天飞**：1–2 个高价值命令，多了等于没有

---

## 与其他 skill 的边界

- 与 **`/init`**（CLAUDE_CODE_NEW_INIT=1 多阶段版）：`/init` 只生成 CLAUDE.md / skills / hooks 三类；本 skill 多 5 类（settings.json、settings.local.json、.gitignore、.mcp.json、commands、agents），并加项目类型 profile + 个人/团队/公开模式区分
- 与 **`claude-automation-recommender`**：那个是"现有项目体检"（read-only 推荐），本 skill 是"从 0 → 1 配齐"（实际生成文件）
- 与 **`claude-md-improver`**：那个改已有 CLAUDE.md，本 skill 不覆盖已有 CLAUDE.md（检测到则跳到 audit 模式）
- 与 **`skill-creator`**：那个建一个新 skill；本 skill 推荐"从已装 plugin 里挑哪些 skill 要 enable"

---

## 参考文件

| 文件 | 何时读取 |
|------|----------|
| `references/profile-ml-research.md` | Phase 3 选 ML 研究 |
| `references/profile-web-app.md` | Phase 3 选 Web app |
| `references/hooks-patterns.md` | 生成 settings.json hook 块时 |
| `references/permissions-deny-presets.md` | Phase 4 第 4 题答完后 |

---

## 调研依据（设计来源）

- Anthropic best-practices：CLAUDE.md "Would removing this cause Claude to make mistakes? If not, cut it"
- Anthropic best-practices：Hooks 是 deterministic，CLAUDE.md 是 advisory
- Anthropic memory doc：CLAUDE_CODE_NEW_INIT=1 多阶段流程是官方雏形（本 skill 是其超集）
- HumanLayer 博客：< 60 行 root CLAUDE.md / WHY-WHAT-HOW 框架
- Anthropic claude-automation-recommender：信号 → 推荐映射 + 数量节制
- abhishekray07/claude-md-templates：Global / Project / Local / Rules / Workflows 五层
- ETH Zurich 研究：auto-generated 配置文件让 agent "20% more expensive"——所以**强制 dry-run + 用户确认**是核心约束
