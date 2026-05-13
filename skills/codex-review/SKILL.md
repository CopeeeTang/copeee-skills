---
name: codex-review
description: Use Codex to review code changes AND optionally execute fixes. Two modes — (1) review-only (默认，输出 findings 不动代码); (2) review-and-fix (autonomous, 找出 BLOCKER/MAJOR 后直接派 codex exec 修，最多 N 轮，每轮 Claude 重审). TRIGGER when 用户要 review 代码 / audit a diff / inspect uncommitted work / check branch vs base / 用 codex 修 bug / "review 完顺便修" / "review and fix" / "review 并改" / "review 后自动修"; user mentions /codex-review or invokes Codex for code work. DO NOT trigger for: 单纯写新代码 / feature implementation without prior review intent (let user pick the right entry point), broad architecture discussion without concrete diff.
---

# Codex Review (+ optional fix)

Codex 既是 reviewer 也是 executor。两种模式：

| Mode | 触发 | Codex 做什么 | Claude 做什么 |
|------|------|--------------|---------------|
| **review-only** | 默认 / 用户只说"review" | 跑 `codex exec review`，输出 findings | 把 findings 摘要给用户 |
| **review-and-fix** | 用户提到"修"/"fix"/"自动改" / 被 ultra-plan 类 orchestrator 调用 | review → 输出 findings → 派 `codex exec --full-auto` 按 findings 修 → 重审，最多 N 轮 | 编排 + 在每轮之间 judge 是否还需要再修 |

## Core Rule

- review-only 模式：Codex 不动代码，只输出 findings.md
- review-and-fix 模式：Codex 先 review、找出 BLOCKER/MAJOR 后**自动**修，每轮修完 Claude 跑一次自检
- 模式选择：默认 review-only；用户表达"修"/"fix"/被 orchestrator 调用时 → review-and-fix

## When to Use

Use this skill when the request is about:
- reviewing code (review-only)
- checking Codex-written code or Claude-written code (review-only)
- auditing a diff (review-only)
- inspecting uncommitted changes (review-only)
- comparing a branch against a base branch (review-only)
- finding bugs, regressions, missing tests, or risky assumptions (review-only)
- **review 完后顺便把 BLOCKER/MAJOR 修了**（review-and-fix）
- **review、修、再 review 的小循环**（review-and-fix）

Do not use this skill for:
- pure feature implementation without any prior review intent (let user pick the right skill — usually they want planning, not review)
- broad architecture discussion without a concrete diff

## Command Selection

Choose the narrowest review scope that matches the task.

### Uncommitted changes

```bash
codex exec review --uncommitted
```

Use when the target is the current working tree.

### Branch diff

```bash
codex exec review --base main
```

Use when the target is the current branch versus a base branch.

### Single commit

```bash
codex exec review --commit <sha>
```

Use when the user wants review for one specific commit.

### Focused review instructions

```bash
codex exec review --base main "Focus on correctness, regressions, edge cases, and missing tests. Findings first."
```

Add a custom prompt only to focus the review. Do not restate obvious instructions.

## Review Priorities

Bias the review toward:
- behavioral regressions
- correctness bugs
- missing validation
- edge cases
- unsafe assumptions
- missing or weak tests
- API or interface breakage

Avoid spending review budget on style nits unless the user explicitly asks for them.

## Output Format

Present findings first.

Use this structure:
1. `Findings`
2. `Open Questions`
3. `Residual Risk`
4. `Change Summary` (optional, short)

Each finding should include:
- severity: critical / high / medium / low
- file and line if available
- what is wrong
- why it matters
- what scenario breaks

If no findings are found, say that explicitly and mention any testing or context limits.

## Review Discipline

- **Review-only mode 严禁 fix**：在 review-only 调用下，Codex 不许动代码。把这条强约束写进 prompt。
- Review-and-fix mode 才允许动代码，且必须先有 findings.md
- Do not give generic praise
- Do not bury findings under summary
- Do not claim something is safe without evidence
- If verification is missing, say so plainly

## Default Prompt Template (review-only)

Use this when the user did not provide custom review instructions:

```text
Review the changes for correctness, regressions, edge cases, and missing tests. Prioritize concrete findings with file references. Findings first. Do not focus on style unless it affects behavior. Do NOT modify any files — this is review-only.
```

## Fix Mode — review-and-fix loop

触发条件之一：
- 用户消息含 "fix" / "修" / "review 并改" / "review 完直接修" / "review and fix"
- 被 orchestrator（如 ultra-plan）调用且明确要 auto-fix
- 用户给出的 findings.md 路径并要求"按这个修"

流程：

```bash
# 1. 先 review 出 findings.md（review-only prompt）
codex exec review --uncommitted \
  > findings.md
# 或: codex exec review --base main > findings.md

# 2. Claude 读 findings.md，判断有没有 BLOCKER / MAJOR
#    没有 → 直接交 findings；只有 MINOR → 列在汇报里但不修

# 3. 有 BLOCKER 或 MAJOR → 启 fix loop
iteration=1
MAX_ITER=${MAX_ITER:-2}

while [ "$iteration" -le "$MAX_ITER" ]; do
  codex exec --full-auto -c 'sandbox_mode="danger-full-access"' "$(cat <<EOF
被 codex-review skill 第 $iteration 轮 fix 模式调用。
findings.md: <绝对路径>

按 findings.md 里 severity = BLOCKER 和 MAJOR 的条目逐条修。
约束:
- 不修 MINOR（用户没要求）
- 修复同时不要破坏其他通过的测试
- 如某条修复需要新增外部依赖（新 API key / 装新 deps）→ 停下来在 stdout 输出
  'DEP_NEEDED: <什么 dep>'，由 Claude 上报用户

完成后跑相关测试做自检（grep findings 里的 test 路径 + 相关 git diff）。
EOF
)" 2>&1 | tee fix_iter${iteration}.log

  # Claude 重审：再次跑 review-only 看 findings 还剩什么
  codex exec review --uncommitted > findings.md

  # 判断是否还要继续
  if grep -qE "^\\s*##\\s*(BLOCKER|MAJOR)" findings.md; then
    iteration=$((iteration+1))
  else
    break
  fi
done
```

每轮上限默认 `MAX_ITER=2`。轮数上限改：`MAX_ITER=3` 之类传入。

**fix loop 退出后**：
- 全绿 → 汇报"修完，N 轮，所有 BLOCKER/MAJOR 已清"
- 仍有 BLOCKER → 汇报"修了 N 轮仍有 BLOCKER，原因 / 需要人工"
- 触发 `DEP_NEEDED` → 转用户拍板（"是否同意新增 <dep>"）

## Fallback

If `codex exec review` is unavailable, fall back to:

```bash
codex exec -s read-only "Review the current changes for correctness, regressions, edge cases, and missing tests. Findings first with file references."
```

State clearly that this is a fallback path. Fallback path 不支持 review-and-fix 模式。

## 与 ultra-plan 的关系

ultra-plan **不再**调用本 skill 做 Phase 4a 的初次 review（那一步现在是 Claude 自己读 diff）。本 skill 现在是：
- **standalone**：用户直接 `Skill(codex-review)` 调用
- **可被其它 orchestrator 调用**：当某个 orchestrator 想"用 Codex 修 codex 自己写的代码"时，本 skill 是入口

ultra-plan Phase 4c auto-fix 是**直接派 `codex exec --full-auto`**，不绕本 skill —— 因为它有自己的 findings.md 来源（Claude review 出来的）。
