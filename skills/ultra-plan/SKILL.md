---
name: ultra-plan
description: Use when user invokes /ultra-plan to run an end-to-end loop — interview (clarify + write spec) → execute (via writing-plans or spawn) → evaluate (Codex review + AC check) → report. Default Autonomous mode: Phase 1 talks spec clear then AI runs without interrupting user until final report. `/ultra-plan --collaborative` switches to step-by-step user confirmation.
user-invocable: true
---

# Ultra-Plan — Scheduler for Long-Running Loops

## Overview

`/ultra-plan` 是**高层 scheduler**，编排 interview → plan → spawn → evaluate 四个阶段成一次完整 loop。核心诉求：用户给出需求，AI 问清楚后自己跑完整个链条，最后交一份报告。

**核心原则：纯 SKILL.md + 一个 sync 脚本**。不带渲染器、不带 server、不带模板引擎。所有产物（spec / findings / ac_results / final_report / 临时 HTML）都是**一次性文件**，Claude 在需要时按照本 SKILL.md 指令即时生成。

## When to Use

- 用户有明确任务目标（不是探索性想法），希望扔给 AI 去做
- 任务需要多步执行（改代码 + 跑测试 + 评估）
- 用户不想被中间过程打扰，只看最终报告
- 需要外部 evaluator（Codex 交叉 review + AC 机器评估）保证质量

## When NOT to Use

- 纯探索性需求（没有明确完成标准）→ `/brainstorm`
- 简单一步任务 → 直接执行
- 用户想实时参与每步决策 → 用 `--collaborative` 或直接 `/interview` + `/spawn`

## Dual Mode

| Mode | Trigger | Phase 2 行为 | Phase 4 失败 |
|------|---------|-------------|---------------|
| **Autonomous** (默认) | `/ultra-plan <task>` | AI 按 spec 自选执行策略 | 汇报 final_report，不自动修 |
| **Collaborative** | `/ultra-plan --collaborative <task>` | AskUserQuestion 4 选项让用户拍板 | 汇报 + 4 选项问用户 |

## Phase 0: Mode Detection

1. 解析 `--collaborative` 或 `-c` flag → `mode = collaborative`
2. 否则 → `mode = auto`
3. 如果 prompt 已含 spec 文件路径（`docs/orchestrator/specs/*.md`）→ 跳过 Phase 1，直接进 Phase 2
4. 把 `mode` 写入后续产出 spec 的 frontmatter

## Phase 0.5: Bootstrap TodoList (关键)

**进入 Phase 1 前必须做这一步**。用 `TaskCreate` 立刻把 6 个 Phase 写成任务清单，让 spinner 持续显示进度，同时给 AI 自己一个"下一阶段已等待"的视觉信号——避免每阶段结束后误以为要用户确认：

```
TaskCreate: "Phase 1a — Codebase Scan (自己读代码库)"
TaskCreate: "Phase 1b — Interview (只问 genuine_unknowns)"
TaskCreate: "Phase 2 — Plan Decision"
TaskCreate: "Phase 3 — Execute"
TaskCreate: "Phase 4 — Evaluate (Codex + AC + auto-fix)"
TaskCreate: "Phase 5 — Chat 汇报"
```

每完成一个 phase 立刻 `TaskUpdate` 标 completed，**同一轮**把下一 phase 标 in_progress。两动作连在一起做，不要中间插用户交互。

这个 TodoList 是 **autonomous mode 的防线**：只要看到 pending tasks，继续执行；不要问"要我继续吗"。

## Phase 1a: Codebase Scan (提问前先自己查)

**在调用 interview-mode 之前**，ultra-plan 自己先做一轮**静默探索**（不打扰用户），把能从代码里读出来的东西读出来。这是 Opus 4.7 autonomous 精神的核心 —— 能从文件里推断的**绝不问**用户。

扫描清单（按顺序执行，每项 1-2 个工具调用）：

1. **项目身份**: 读 `CLAUDE.md` / `README.md` / `AGENTS.md`（如存在）
2. **技术栈**: 读 `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / `requirements.txt`（存在哪个读哪个，不存在跳过）
3. **目录结构**: `ls` 顶层 + 1 级展开（快速把握代码组织）
4. **关键词命中**: 按用户 prompt 里的关键词 grep 现有代码（例："加一个 login 函数" → grep `login\|auth` 定位现有实现或缺失）
5. **相关测试**: 若有 `tests/` 或 `__tests__/`，看测试命名惯例和跑测命令

扫描产出（内部记录，下一步喂给 interview）：

```
codebase_scan:
  project: <从 CLAUDE.md / README 推断的项目描述>
  tech_stack: <从依赖文件推断>
  conventions:
    - <命名风格：snake_case / camelCase>
    - <测试框架：pytest / jest / go test>
    - <目录惯例>
  existing_related:
    - <已有的相关文件和位置>
  defaults_inferred:
    - <AI 凭扫描结果能填好的 spec 默认值，列出来>
  genuine_unknowns:
    - <扫完依然没法推断、必须问用户的点>
```

**关键规则**：
- `defaults_inferred` 里的东西 → **不要在 interview 里问**，直接预填进 spec，在 `Auto-Decision Log` 里记一句"从 X 推断得到 Y"
- `genuine_unknowns` 里的东西 → **这才是 interview 该问的**

**什么永远不问（因为代码会告诉你）**：
- ❌ "这是什么语言/框架？" → 读 `package.json` 或后缀
- ❌ "测试怎么跑？" → 读 `package.json scripts` / `pyproject.toml`
- ❌ "代码风格是 snake_case 还是 camelCase？" → 看现有文件
- ❌ "要放哪个目录？" → 看现有同类文件的位置
- ❌ "要不要加测试？" → 看项目是否有测试目录和覆盖率惯例
- ❌ "要兼容哪个版本？" → 读依赖版本锁定文件

**什么必须问（因为代码不会告诉你）**：
- ✅ 这次要做什么具体行为 / 功能（用户意图）
- ✅ 成功的硬标准（Acceptance Criteria，必须用户亲自确认）
- ✅ 有没有不能碰的东西（Constraints）
- ✅ 用户的品味偏好（命名某个新概念、UX 风格等）

## Phase 1b: Interview (强制)

调用 `interview-mode` skill，**把 Phase 1a 的扫描结果塞进 prompt**，这样 interview 不会重复问已知信息。prompt 模板：

```
被 ultra-plan 调用，mode={auto|collaborative}。
产出 spec 到 docs/orchestrator/specs/YYYY-MM-DD-<topic-slug>.md（按下方 schema）。
日期+slug 冲突 → 追加 -v2, -v3 不覆盖。

## 已完成的 Codebase Scan（ultra-plan Phase 1a 产出）
<把 Phase 1a 的 codebase_scan 整块贴进来 —— 项目、技术栈、约定、existing_related、
 defaults_inferred、genuine_unknowns>

## 必须追问到完备的字段
  - Intent (1-2 句)
  - Context (背景/现有系统 —— 若 Phase 1a 已推断出来，直接填，不问)
  - Scope: In / Out
  - Acceptance Criteria — Auto-Executable (至少 1 条 CMD 或 METRIC 行)
  - Acceptance Criteria — Manual Check (可为空)
  - File Locations: Modify / Create / Test (Phase 1a 的 existing_related 应能预填大部分)
  - Constraints
  - Execution Strategy: Single | Todo | Teams + Rationale
  - frontmatter 字段: mode, ralph_loop

## 提问纪律
- 只问 genuine_unknowns 里的点
- defaults_inferred 的内容用"确认式提问"而不是"开放式提问"：
    ❌ "用什么测试框架？"
    ✅ "我看到 package.json 里有 jest，默认用 jest 对吗？(推荐) / 换成 vitest / 其他"
- 任何能从 codebase_scan 得出的默认值 → 直接填 spec，不问。在 spec 的 Auto-Decision Log
  里记 "Inferred from <source>: <value>"

不输出 "Transition to Next Phase"。返回 spec 路径给 ultra-plan。
```

### Spec Schema

````markdown
---
topic: <kebab-case-topic>
slug: <slug>
created: YYYY-MM-DD
orchestrator: ultra-plan
mode: auto | collaborative
ralph_loop: false
source: /ultra-plan "<原始用户输入>"
---

# <Topic Title> — Requirements Spec

## Intent
[1-2 句]

## Context
[背景]

## Scope
- In scope: [...]
- Out of scope: [...]

## Acceptance Criteria — Auto-Executable
> Phase 4b 机器执行。必须是可测量指令。

- [ ] CMD: `<shell command>` → <expected>
- [ ] METRIC: `<measurement command>` → <threshold>

## Acceptance Criteria — Manual Check
> Phase 4c 写进 final_report 作为 checklist，人工勾选。

- [ ] <人工判断项>
  - 检查方式: <操作步骤>
  - 备注:

## File Locations
- Modify: <path:lines>
- Create: <path>
- Test: <path>

## Constraints
- [...]

## Key Insights (from interview)
- [...]

## Execution Strategy
- Recommended: Single | Todo | Teams
- Rationale: [...]
- Parallelization: [...]

## Auto-Decision Log
> Autonomous mode 下 AI 自动决策记录，orchestrator 运行中追加。
````

## Phase 2: Plan Decision

### Autonomous Mode (默认)

不打扰用户。按 `spec.ExecutionStrategy.Recommended` 字段决定下一步：
- `Single` → 本 session 执行（不分派）
- `Todo`   → Skill(writing-plans) → executing-plans / subagent-driven-development
- `Teams`  → Skill(spawn)

如果 `spec.ExecutionStrategy` 缺失或矛盾（例如 Recommended 和 Rationale 互相否定）→ 属 "Spec 内部矛盾" 关键决策，必须 AskUserQuestion。

### Collaborative Mode

AskUserQuestion 让用户拍板：

```json
{
  "questions": [{
    "question": "如何执行 spec 定义的任务？",
    "header": "执行路径",
    "options": [
      {"label": "产出 TDD 计划 (Todo)", "description": "调 writing-plans 产 bite-sized 步骤"},
      {"label": "直接派发 (Teams)", "description": "调 spawn 分析拓扑并派 agent"},
      {"label": "单 session 执行 (Single)", "description": "主 session 直接实现"},
      {"label": "修改 spec 后重跑", "description": "回 Phase 1 补齐/调整 spec"}
    ],
    "multiSelect": false
  }]
}
```

## Phase 3: Execute

按 Phase 2 选择的路径，调用对应 skill，始终注入 spec 路径：

### Todo 路径
```
Skill(writing-plans)
prompt: "被 ultra-plan 调用，读取 docs/orchestrator/specs/<spec-file> 作为唯一权威需求。
        spec.AcceptanceCriteria 是 Phase 4 评估依据，不要修改或降级。
        Constraints 是硬约束。File Locations 是改动范围。"
→ writing-plans 产 plan → 接 executing-plans 或 subagent-driven-development
```

### Teams 路径
```
Skill(spawn)
prompt: 同上。spawn 识别 spec 路径 → 跳过自身澄清段。
```

### Single 路径
主 session 直接按 spec 实现。不调用其它 skill。

## Phase 4: Evaluate (Codex review + auto-fix, 最多 2 轮)

### 4a. Codex Cross-Review

```bash
mkdir -p docs/orchestrator/evaluations/<spec-slug>

codex exec -c 'sandbox_mode="danger-full-access"' \
  "Review uncommitted changes against this spec: <spec-path>.
   Focus on (priority):
   1. Acceptance Criteria 是否真的会通过（逐条）
   2. Constraints 是否被违反
   3. Regression / edge cases / security
   Output: findings.md, one finding per section, severity tag [BLOCKER|MAJOR|MINOR]." \
  > docs/orchestrator/evaluations/<spec-slug>/findings.md
```

### 4b. Auto-Executable AC 逐条执行

解析 spec 的 "Acceptance Criteria — Auto-Executable" 段。每条：
- CMD 行 → `bash -c "<cmd>"`，记 stdout / stderr / exit_code
- METRIC 行 → 跑命令，按 regex 提取数值，对比阈值

写入 `docs/orchestrator/evaluations/<spec-slug>/ac_results.json`：

```json
[
  {"criterion": "pytest tests/auth/ -v", "type": "CMD", "status": "PASS", "exit_code": 0, "stdout_head": "…"},
  {"criterion": "login p50 < 200ms", "type": "METRIC", "status": "FAIL", "measured": 345, "threshold": 200}
]
```

### 4c. Auto-Fix Loop (Autonomous 核心)

Phase 4a + 4b 跑完后，若有以下之一 → **立刻自动修**（不问用户）：
- Codex findings 含 `BLOCKER` 或 `MAJOR`
- Auto-Executable AC 有 FAIL

修复流程：

```
iteration = 1
while iteration <= 2 and (has_blocker_or_major_findings or has_ac_fail):
    # 派 spawn subagent 修
    Skill(spawn)
    prompt: "被 ultra-plan Phase 4 调用修 bug。
            Spec: <spec-path>
            Codex findings: <findings.md path>
            AC results: <ac_results.json path>
            修复以下具体问题：
              - <failing AC 1>
              - <BLOCKER finding 1>
            约束: 不得违反 spec.Constraints; 不得降级 spec.AcceptanceCriteria。
            若唯一可行修复会违反 Constraints → 停下来返回 'CONSTRAINTS_CONFLICT: <原因>'，
                由 orchestrator 决定是否上报用户。"

    # 修完重新跑 4a + 4b
    重跑 codex review → findings.md (overwrite)
    重跑 auto AC → ac_results.json (overwrite)
    iteration += 1

# 退出循环后：
if 仍有 BLOCKER / AC FAIL:
    → 继续到 4d，把"无法自动修复的问题"明确标出来
else:
    → 继续到 4d，全绿
```

**什么时候不自动修、转而打扰用户**：
- 修复尝试返回 `CONSTRAINTS_CONFLICT` → 属"Constraints 违反"关键决策
- 修复需要新增外部依赖（新 API key / 装新 deps）→ 属"外部 API/资源依赖"关键决策
- 修了 2 轮仍不过 → 不再修，进 4d 标注"自动修复失败，需要人工"

**什么情况不触发自动修**：
- Codex 只有 `MINOR` findings（命名风格、轻微冗余等）→ 不修，4d 列在"可选改进"供用户看
- Manual Check AC 为 FAIL → 本来就是人工项，不该自动修

### 4d. 生成 final_report.md（归档用）

> ⚠️ **final_report.md 是归档，不是主输出**。主输出是 4e 的 chat 汇报。

写入 `docs/orchestrator/evaluations/<spec-slug>/final_report.md`，结构：

````markdown
# <topic> — Final Report

**Date:** YYYY-MM-DD
**Mode:** auto | collaborative
**Spec:** docs/orchestrator/specs/<spec-file>

## Summary
- **Status:** ✅ All auto AC passed, no BLOCKER findings / ⚠️ Partial: N failures
- **Phase 3 execution:** <what was built, 1-3 sentences>
- **Files changed:** <list or `git diff --stat`>

## Phase 4a Codex Findings
### BLOCKER
- <finding or "(none)">
### MAJOR
- <finding or "(none)">
### MINOR
- <finding or "(none)">

## Phase 4b AC Results
| Criterion | Type | Status | Details |
|-----------|------|--------|---------|
| <raw criterion string> | CMD | ✅ PASS | exit 0 |
| <raw criterion string> | METRIC | ❌ FAIL | measured 345, threshold 200 |

## Phase 4c Manual AC Checklist
> 以下 AC 无法自动执行，请人工验证后在本文件勾选。

- [ ] <item 1>
  - 检查方式: <操作步骤>
  - 备注:
- [ ] <item 2>
  - 检查方式: ...
  - 备注:

## Auto-Decision Log (autonomous mode only)
> 本次运行中 AI 做过的"不打扰的决策"。

- <decision 1>
- <decision 2>

## Recommended Next Steps
> 针对失败 AC / BLOCKER findings 的建议。**不自动执行**，由用户决定。

- 建议 1
- 建议 2
````

### 4e. Chat 汇报（主输出，最关键）

Phase 4 完成后**直接在 chat 输出**以下结构化文字——这是用户唯一真正看的东西。不要只给 final_report.md 路径让用户自己去看。

汇报模板（必须包含这 4 个段，按顺序）：

```markdown
## ✅/⚠️ 完成: <topic>

**做了什么** (2-4 句)
<用动词主导：添加了 X 函数 / 修改了 Y 文件 / 跑通了 Z 测试。不要只贴文件名>

**检查结果**
- Auto AC: <N/M> 通过<若全过就写 "全过"，否则列出失败的>
- Codex findings: <BLOCKER: N, MAJOR: N, MINOR: N>（被自动修的标✓，未修的简述）
- Auto-fix 迭代: <N> 轮（如果有）

**⚡ 需要你拍板** (如果有关键决策触发 或 auto-fix 失败项)
- <具体问题 1>: <两个选项，一个推荐>
- <具体问题 2>: <...>

**📋 待人工验证** (Non-auto AC，通常 1-3 条，不用超过)
- [ ] <item 1> —— <如何检查>
- [ ] <item 2>

**下一步建议** (一句话)
<最常见的下一步：commit / 跑更多测试 / 部署 / 继续开发 XXX>

<详细归档: docs/orchestrator/evaluations/<slug>/ — 有需要再看>
```

**什么不该放在 chat 输出**：
- ❌ 完整的 findings 列表（放 findings.md 里）
- ❌ 每条 AC 的命令和 stdout（放 ac_results.json 里）
- ❌ 详细的 Auto-Decision Log（放 final_report.md 里）
- ❌ "欢迎回来" / "以下是总结" 之类的开场白
- ❌ Phase 4 流程说明（用户不需要看到内部机制）

**什么必须放在 chat 输出**：
- ✅ 做了什么（动词化的动作描述）
- ✅ 最终状态（绿灯还是有问题）
- ✅ 需要用户拍板的决定（明确列选项）
- ✅ 人工验证 checklist（短，≤5 条）
- ✅ 下一步建议（一句话）
- ✅ 归档路径（一行，不强调）

### 为什么 Phase 4 要 auto-fix

- 用户在 Phase 1 已经定好了 Acceptance Criteria = 验收标准
- AC FAIL 和 BLOCKER findings 是**技术问题**，不是**需要用户价值观判断的事**
- 让 AI 自动修 = 尊重用户时间（这就是 autonomous mode 承诺）
- 2 轮上限 = 防止无限循环烧 token
- 仍不过的 → 清晰告诉用户**什么修不了 + 为什么**，不要藏起来

## Key Decision Table

Autonomous mode 下，AI 根据下表判断是否打扰用户：

| 类型 | 判定 | 示例 | 处理 |
|------|-----|------|------|
| 用户意图不明确 | ✅ 必须问 | prompt 太短/多义，AI 判断"我在猜" | AskUserQuestion 列 2-4 种解读 |
| 不可逆副作用 | ✅ 必须问 | `git push --force`, `rm -rf`, prod 部署 | AskUserQuestion 确认 |
| 品味/价值观 | ✅ 必须问 | UI 风格, 命名偏好, API 风格 | AskUserQuestion 给选项 |
| Spec 内部矛盾 | ✅ 必须问 | 两条 AC 互相打架 | 展示矛盾让用户取舍 |
| Constraints 违反 | ✅ 必须问 | 唯一修复路径违反 Constraints | 让用户选放宽/保留/放弃 |
| 外部 API/资源依赖 | ✅ 必须问 | 需新 API key、新 deps、新云资源 | 说明原因 |
| 实现技术选型 | ❌ AI 自选 | `requests` vs `httpx` | 记录到 final_report |
| 需求默认补全 | ❌ AI 自选（借模糊时问）| "加个 login" → email+password | 记到 Auto-Decision Log |
| Phase 3 内部修复 | ❌ AI 自选 | teammate 跑 test 报错自修 | 在 Phase 3 scope 内 |
| 文件结构细节 | ❌ AI 自选 | 拆文件粒度、module 组织 | 遵循项目惯例 |
| Phase 3 执行策略 | ❌ AI 自选 | Single vs Todo vs Teams | 用 spec.Recommended |
| Phase 4 AC FAIL / BLOCKER / MAJOR | ❌ AI 自动修 | 报错、测试挂、regression | 派 spawn 修 → 重跑 4a/4b，最多 2 轮 |
| Phase 4 MINOR findings | ❌ AI 自选不修 | 命名风格、轻微冗余 | 列在 chat 汇报的"可选改进"供用户看 |
| Phase 4 auto-fix 失败 (2 轮仍不过) | — | 2 轮修复后还有 BLOCKER/FAIL | 停修，4e chat 汇报里明确列"未修的问题 + 原因" |

**核心原则**：
1. 真正会把事情搞砸的决策 → 必须打扰
2. AI 判断"我在猜用户意图"时 → 必须打扰（哪怕技术上能跑）
3. 其他默认不打扰 → 记 `Auto-Decision Log` 和 `final_report.md`

## Anti-Pattern: "要我继续吗？"

Autonomous mode 下，**阶段切换不是打扰点**。以下所有行为都是违反契约：

| ❌ 违反契约 | ✅ 正确做法 |
|-----------|-----------|
| "Phase 1 完成了，要我继续吗？" | 直接 TaskUpdate → 进 Phase 2 |
| "spec 写好了，你先看一下再继续？" | 直接进 Phase 2，spec 是否 OK 交给 Phase 4 Codex review |
| "确认没问题回复'继续'或'go'" | 不需要确认，pending task 在等就是 go 信号 |
| "我稍微停一下让你过一眼" | 不要停。任何"停一下"都是违反 autonomous |
| 把 spec 摘要列出来请用户快速 review | spec 文件已在 disk，用户要看自己会看 |
| Codex review 发现 BLOCKER/MAJOR → 问用户"派人修还是手动改？" | 直接派 spawn 修，最多 2 轮。修完汇报结果，不问方法 |
| AC FAIL → "你想怎么处理？" | AC 是用户自己在 Phase 1 定的 → FAIL 是技术问题，直接 auto-fix |
| 最终只回复 "done, see docs/orchestrator/evaluations/.../final_report.md" | chat 里**直接**写出：做了啥 + 检查结果 + 待拍板 + 下一步。文件归档只作附注 |
| 把 findings.md 完整内容粘进 chat | chat 只放分级计数（BLOCKER: N, MAJOR: N, MINOR: N），详情在归档文件里 |
| 上来就问"你用什么语言/框架/测试？" | 先做 Phase 1a Codebase Scan，读 package.json / README / CLAUDE.md 自己推断，confirm 式问（默认值 + 推荐标）|
| 问"代码放哪个目录？" | 看现有同类文件在哪，直接预填 spec.FileLocations，不问 |
| 问"要不要加测试？" | 看 `tests/` 目录是否存在、覆盖率惯例，默认跟随项目习惯 |

**判断是否该打扰的唯一标准**：是否触发"关键决策表"12 类里的 ✅ 行。`spec 已写好` 不在里面。`意图不明确` 在里面——但如果 interview 都没问出来，就别指望在 Phase 2 起点问出来。

用户选择 `/ultra-plan` (autonomous mode) 的语义 = **授权跑完整个 loop**，不是"每步等我点头"。想要每步点头的用户会用 `--collaborative`。

**如果你（AI）此刻正想问"要继续吗"——停下这个念头，直接继续**。spec 的瑕疵会在 Phase 4 被发现，修复决策会在 final_report 里让用户事后看。Autonomous mode 的全部价值就在于用户不在场也能跑完。

---

## Phase 切换纪律

每完成一个 phase：
1. 立刻 `TaskUpdate <current-phase>: completed` + `TaskUpdate <next-phase>: in_progress`（同一轮工具调用内）
2. **不要**输出"Phase X 完成，接下来..."的旁白
3. **不要**在 phase 之间插入任何 AskUserQuestion，除非触发关键决策表
4. Phase 1 → Phase 2 之间没有用户交互，不需要摘要 spec 内容（spec 已存盘，用户需要时自己看）
5. Phase 2 → Phase 3 之间没有用户交互（auto mode），直接调下游 skill

## Operating Principles (Opus 4.7 best practices)

1. **Upfront specification**: Phase 1 把 intent / constraints / AC / file locations 一次问全，不要让 Phase 3 executor 再回头问
2. **Batch interactions**: AskUserQuestion 1-4 题/次，紧耦合时批量；减少 user turn 数
3. **Auto mode as default**: Phase 2/4 默认不打扰，靠"关键决策表"判断介入
4. **Spec is source of truth**: Phase 3 所有 agent 以 spec 为权威；spec 没写的 = 不做；要调整 → 回 Phase 1 重跑 `-v2`
5. **External evaluator + bounded auto-fix**: Phase 4 用 Codex 交叉 review；对 BLOCKER / MAJOR / AC FAIL 自动派 spawn 修（最多 2 轮），MINOR 不修只列。AC FAIL 是技术问题，不需要用户拍板价值观
6. **Don't notify about cache misses**: 中间进度用 TaskUpdate spinner，不打文字
7. **Ask when guessing user intent**: 感到"我在猜"必须 AskUserQuestion（关键决策表第 1 行）
8. **Chat output > file archive**: Phase 4 主输出是直接写在 chat 里的结构化汇报（做了啥 + 检查结果 + 拍板项 + 下一步），不是 "final_report.md 路径让你自己看"。文件归档是 secondary

## Integration Contracts

### 与 interview-mode
见 Phase 1 的 prompt 模板。interview-mode 识别 "被 ultra-plan 调用" 信号 →
- 走标准 AskUserQuestion 澄清
- 追加对 AC (auto + manual) 和 File Locations 的显式追问
- Summary 写入 spec 路径（按 schema），不输出 Transition 章节

### 与 writing-plans / spawn
调用 prompt 含 spec 路径；下游 skill 以 spec 为唯一权威。

### spawn 的 opt-in 行为
spawn 检测到 prompt 含 `docs/orchestrator/specs/*.md` 路径 → 跳过自身澄清段，直接读 spec 作为权威需求源。

## File Layout (runtime 产物)

```
docs/orchestrator/
├── specs/
│   └── YYYY-MM-DD-<slug>.md          # Phase 1 产出
└── evaluations/
    └── YYYY-MM-DD-<slug>/
        ├── findings.md                # Phase 4a
        ├── ac_results.json            # Phase 4b
        └── final_report.md            # Phase 4c
```

**命名冲突规则**：同日期同 slug 冲突 → 追加 `-v2`, `-v3`，不覆盖。

## Sync

**2026-04-22 起**：`ultra-plan` / `interview-mode` / `spawn` 三个 skill 在本地走 symlink：

```
~/.claude/skills/ultra-plan  →  copeee-skills/skills/ultra-plan  (实文件, git-tracked)
~/.claude/skills/interview-mode → copeee-skills/skills/interview-mode
~/.claude/skills/spawn       →  copeee-skills/skills/spawn
```

编辑任一侧都改的是同一份文件，**不需要再跑 sync**。`sync-skills.sh` 只对非 symlink 的 skill 有用（新加了 symlink 检测，symlink 会自动跳过）。

其他 skill 仍用 `sync-skills.sh push/pull/diff` 管理。
