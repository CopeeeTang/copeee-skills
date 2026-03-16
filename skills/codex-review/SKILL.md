---
name: codex-review
description: Use when the user wants OpenAI Codex to review code changes, audit a diff, inspect uncommitted work, or provide findings on a branch, commit, or patch
---

# Codex Review

Use Codex as a reviewer, not as an implementer.

## Core Rule

For review tasks, prefer `codex exec review` over generic `codex exec`.

Do not turn review into implementation unless the user explicitly asks for fixes.

## When to Use

Use this skill when the request is about:
- reviewing code
- checking Claude-written code
- auditing a diff
- inspecting uncommitted changes
- comparing a branch against a base branch
- finding bugs, regressions, missing tests, or risky assumptions

Do not use this skill for:
- feature implementation
- refactoring
- writing new code
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

- Do not silently fix code during review
- Do not give generic praise
- Do not bury findings under summary
- Do not claim something is safe without evidence
- If verification is missing, say so plainly

## Default Prompt Template

Use this when the user did not provide custom review instructions:

```text
Review the changes for correctness, regressions, edge cases, and missing tests. Prioritize concrete findings with file references. Findings first. Do not focus on style unless it affects behavior.
```

## Fallback

If `codex exec review` is unavailable, fall back to:

```bash
codex exec -s read-only "Review the current changes for correctness, regressions, edge cases, and missing tests. Findings first with file references."
```

State clearly that this is a fallback path.
