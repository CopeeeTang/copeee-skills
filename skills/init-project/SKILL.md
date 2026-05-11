---
name: init-project
description: "Bootstrap a new project's core docs and skeleton files for Claude Code: CLAUDE.md + CLAUDE.local.md (个人偏好) + research-notes.md (合并的研究问题文档) + pyproject.toml/equivalent (template, no install) + .gitignore. Beyond /init: signal-driven detection from project type (ML research / web app / CLI / library / data pipeline), personal vs team vs public sharing modes, dry-run preview before any file is written. Default 最小集 only — slash commands / .claude/settings.json / hooks / agents 都是 opt-in 不默认生成（已有 global dontAsk + all permissions + 已装 plugin 提供 skill）。TRIGGER when: user wants to bootstrap/initialize/configure a new project (greenfield repo, fresh setup, '配置一个新项目', 'bootstrap project', 'init project', 'set up Claude Code for this repo'); user mentions /init-project command; user asks 'how do I configure Claude Code for X kind of project'; user describes a new project + asks what initial docs/skeleton are needed. DO NOT trigger for: editing existing CLAUDE.md to fix one rule (use claude-md-improver), code-level work, single skill creation (use skill-creator), MCP setup question (use claude-automation-recommender)."
---

# init-project — Bootstrap 项目蓝图

## 角色定位

你是项目"打地基"工。你**只画蓝图**——CLAUDE.md / 研究问题文档 / 包管理 manifest / .gitignore。Claude 工具层面的"装修"（settings.json / commands / hooks / agents）默认**不动**，前提：

- 用户全局已经是 `dontAsk` + all-permissions（默认假设）
- 项目级 skill 通过 plugin description 自动触发（不靠 .claude/skills/ 显式 enable）
- venv / 依赖装机 deferred 到用户根据配置选定 backend 后自己做

只在用户**明确要求**时才追加生成 `.claude/settings.json` / `.claude/commands/` / hooks。

---

## 核心原则

1. **信号驱动**：先扫码再提问，不问已能从代码得知的
2. **最小默认**：default artifact 集 = `CLAUDE.md` + 可选 `CLAUDE.local.md` + 研究问题单文件 + manifest + .gitignore
3. **研究问题合并**：多个 RQ 默认进**一个** `research-notes.md`，不拆 `.kiro/specs/<n>/`——等真正分化时用户自己拆
4. **dry-run 优先**：所有文件先打印 preview，用户审过再落盘
5. **个人 vs 团队**：明确分层，个人偏好绝不污染 git

---

## 触发后的执行流程

### Phase 1 — 扫码（自动，0 提问）

并行跑这些探测：

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

输出"已识别"摘要给用户看。

如果检测到 `CLAUDE.md` 已存在 → 转 `claude-md-improver` skill，本 skill 不覆盖已有文件。

### Phase 2 — 项目阶段 + 共享模式（2 题强制）

```
Q1: 项目阶段？
  [a] 全新（greenfield，没写过代码）
  [b] 已有代码，第一次配 Claude Code
  [c] 已有 CLAUDE.md，要做体检 → 转 claude-md-improver 退出

Q2: 谁会用这份配置？
  [a] 仅自己 → 生成 CLAUDE.local.md（如有个人偏好），加入 .gitignore
  [b] 团队共享 → CLAUDE.md 入 git，私有偏好分到 CLAUDE.local.md
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

每勾选一项 → 加载 `references/profile-{type}.md`（当前覆盖 `ml-research` 和 `web-app`）。

### Phase 4 — 关键 dimension（按项目类型选问，避免无用问题）

**ML 研究项目额外问**（参考 `references/profile-ml-research.md`）：
- 研究问题清单（几条？分别是什么？合一个文档还是要拆？）
- 数据在哪？（local / Azure Blob / HF / S3）
- 计算资源？（A100 / 4090 / 集群 / CPU）
- 性能目标？（latency / throughput / accuracy）
- 哪些是**红线规则**（绝不能跨的边界，如"VLM 只用本地"、"ASR 必须并行"）→ 进 CLAUDE.md ⚠️ IMPORTANT 段

**Web app 项目额外问**（参考 `references/profile-web-app.md`）：
- 前端框架？后端运行时？数据库？
- 红线规则（如"prod migration 必须人工 review"）

**通用追问**（仅当用户主动提"我想要 X"时）：
- 想生成 `.claude/settings.json` 收紧 permissions？默认**不生成**
- 想生成 `.claude/commands/` 项目级 slash command？默认**不生成**
- 想配 hook（lint-on-save 等）？默认**不生成**

---

## Phase 5 — Dry-run preview + 用户确认

```
========== DRY-RUN: 4 files will be created ==========
工作目录: <user-dir>
模式: <personal | team | public>

[1/4] CLAUDE.md (62 lines)
---内容---

[2/4] CLAUDE.local.md (18 lines, 个人模式才生成)
---内容---

[3/4] research-notes.md (合并 3 个 RQ 到单文件)
---内容---

[4/4] pyproject.toml (template only — not running `uv sync`)
---内容---

Skipped by default (可手动追加：edit add settings / edit add commands):
  - .claude/settings.json  (你已有全局 dontAsk + all permissions)
  - .claude/commands/*     (建议依赖 plugin skill，不引入项目级 slash command)
  - .gitignore            (skip — 还不是 git repo / 跳过追加)

========== END DRY-RUN ==========

Confirm?
  y           = 全部落盘
  edit N      = 重写第 N 个文件
  skip N      = 不生成第 N 个
  add settings / add commands / add hooks   = 追加 opt-in artifact
  cancel      = 全部放弃
```

用户主动 `add settings` / `add commands` / `add hooks` 才追加。

---

## Phase 6 — 写文件 + 后续指引

```
✓ 已生成 4 个文件

下一步（按需，不强制）：
  1. 写代码前：先选 backend（vLLM / transformers / Whisper backend）→ 然后 `uv sync` 装 venv
  2. 第一次 git init 后：把 CLAUDE.local.md 加入 .gitignore
  3. 出现第二次同样错误 → 加进 CLAUDE.md
  4. 真有项目级 slash 高频 workflow（>5 次/周）时 → `init-project add commands`
  5. 30 天后 review CLAUDE.md，问"删了它 Claude 会不会犯错"——不会就删
```

---

## Artifact 矩阵（new default = minimal）

### Default 生成（默认，不问也生成）

| Artifact | 何时生成 | 大小目标 |
|----------|----------|----------|
| `CLAUDE.md` | 总是 | < 80 行 |
| `CLAUDE.local.md` | 个人模式 + 有个人偏好 | < 30 行 |
| `research-notes.md`（或类似单文件 spec） | 用户提出多个研究问题 | 60–120 行 |
| `pyproject.toml` / `package.json` / 等 | 项目类型 + 语言匹配，**只生成不安装** | < 50 行 |
| `.gitignore` 追加块 | 是 git repo 才追加 | +5 行 |

### Opt-in（用户主动喊 `add ...` 才生成）

| Artifact | 何时生成 |
|----------|----------|
| `.claude/settings.json` | 用户明确要收紧 permissions 或加 env vars 之外的事 |
| `.claude/settings.local.json` | 个人模式 + 有项目专属个人 env（如 SAS token 占位）|
| `.claude/commands/*.md` | 用户给出明确高频 workflow (>5 次/周)|
| `.claude/agents/*.md` | 大项目（>10K LoC）+ 明确多角色需求 |
| `.claude/hooks/*` in settings.json | 用户明确要 lint-on-save / pre-commit 等自动化 |
| `.mcp.json` | 项目有外部依赖（DB / 浏览器测试 / Slack 集成）|
| `AGENTS.md` 软链 | 用户同时用 Codex/Cursor |
| `SPEC.md` 模板 | 用户勾选"我要 spec-driven" |

> **设计判断依据**：用户全局已经是 `dontAsk` + all-permissions 默认 + 已装 plugin 提供 skill 库。再生成项目级 `.claude/settings.json` 是噪音；项目级 slash command 比 plugin skill 触发率低，默认不生成更干净。

---

## 研究问题合并规则

ML / 研究项目常有多个 RQ。**默认合并到 1 个 `research-notes.md`**，结构：

```markdown
# Research Notes — <project-name>

## Problem statement
...

## Research questions
1. RQ1: <一句话>
2. RQ2: <一句话>
3. RQ3: <一句话>

## RQ1 — <title>
- 子问题: ...
- 实验设计: ...
- 评估指标: ...

## RQ2 — <title>
... (同上结构)

## RQ3 — <title>
... (同上结构)

## Engineering constraints
- 红线 1: ...（同步进 CLAUDE.md ⚠️ IMPORTANT）
- 红线 2: ...

## Open questions
- ...

## TODO
- [ ] 数据 schema 确认
- [ ] 评估协议草稿
```

**何时拆分到 `.kiro/specs/<rq>/` 或类似**：
- 用户**明确说**"我要按 spec-driven 跑"
- 单个 RQ 已经分化出 design.md + tasks.md 内容
- 各 RQ 实验设计差异巨大无法在一个文档讲清

默认不拆。

---

## 反模式（必避免）

1. **Kitchen-sink default**：用户没要的 artifact 不生成。`.claude/settings.json` / `.claude/commands/` / hooks 全部 opt-in
2. **过早拆研究问题**：多 RQ 默认进一个 `research-notes.md`；用户主动喊"拆"才分文件
3. **lint 写进 CLAUDE.md**：HumanLayer "Never send an LLM to do a linter's job"——能交给 hook 的事绝不写 prose
4. **个人偏好混进 team CLAUDE.md**：永远分 `CLAUDE.md`（git）vs `CLAUDE.local.md`（gitignore）
5. **盲生成不审**：所有写盘前必走 Phase 5 dry-run，用户能逐文件 edit/skip/cancel
6. **强制 venv 安装**：只生成 `pyproject.toml` 模板，**不**自动 `uv sync` / `pip install`——venv 安装时机由用户根据 backend 选定后自己做
7. **重复 global 配置**：用户 global 已经 `dontAsk` + all-permissions，不要在 `.claude/settings.json` 重复声明同样规则
8. **slash command 满天飞**：默认不生成；用户明确给出高频 workflow 才追加

---

## 与其他 skill 的边界

- 与 **`/init`**（CLAUDE_CODE_NEW_INIT=1 多阶段版）：`/init` 主生成 CLAUDE.md；本 skill 加上 research-notes / pyproject / .gitignore，并支持 opt-in 追加 settings/commands/hooks
- 与 **`claude-automation-recommender`**：那个是"现有项目体检"（read-only 推荐 hook/plugin 等），本 skill 是"从 0 → 1 出最小蓝图"（实际生成文件 + opt-in 扩展）
- 与 **`claude-md-improver`**：那个改已有 CLAUDE.md；本 skill 不覆盖已有 CLAUDE.md（检测到则跳到 audit 模式）
- 与 **`skill-creator`**：那个建一个新 skill；本 skill 只生成项目蓝图，不动 skill 配置

---

## 参考文件

| 文件 | 何时读取 |
|------|----------|
| `references/profile-ml-research.md` | Phase 3 选 ML 研究 |
| `references/profile-web-app.md` | Phase 3 选 Web app |
| `references/hooks-patterns.md` | 仅当用户喊 `add hooks` 时 |
| `references/permissions-deny-presets.md` | 仅当用户喊 `add settings` 时 |

---

## 调研依据（设计来源）

- Anthropic best-practices：CLAUDE.md "Would removing this cause Claude to make mistakes? If not, cut it"
- Anthropic best-practices：Hooks 是 deterministic，CLAUDE.md 是 advisory（但只在需要时加）
- Anthropic memory doc：`CLAUDE_CODE_NEW_INIT=1` 多阶段流程是官方雏形
- HumanLayer 博客：< 60 行 root CLAUDE.md / WHY-WHAT-HOW 框架
- ETH Zurich 研究：auto-generated 配置文件让 agent "20% more expensive"——所以**强制 dry-run + minimal default + 用户确认**是核心约束
