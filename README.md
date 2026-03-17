# copeee-skills

Productivity skills for [Claude Code](https://claude.com/claude-code).

## Installation

```bash
# Step 1: Add as a marketplace source
/plugin marketplace add CopeeeTang/copeee-skills

# Step 2: Install the plugin
/plugin install copeee-skills
```

## Skills

### Workflow & Planning

| Skill | Command | Description |
|-------|---------|-------------|
| **interview-mode** | `/interview` | Structured requirements clarification before planning. Uses interactive `AskUserQuestion` UI for precise multi-choice questioning. |
| **spawn** | `/spawn <task>` | Task execution topology router. Analyzes dependencies and routes to 4 execution modes: Background Subagents, Agent Teams, Task Todo, or Codex delegation. |
| **save-session** | `/save-session [project]` | Save session action history before context compaction. Extracts key decisions, data, and next steps via subagent. |

### Code Quality

| Skill | Command | Description |
|-------|---------|-------------|
| **code-simplifier** | `/simplify` | Refine recently modified code for clarity and maintainability while preserving functionality. |
| **codex-review** | `/codex` | Use OpenAI Codex as a code reviewer — audits diffs, branches, and uncommitted changes with structured findings. |

### Research & Knowledge

| Skill | Command | Description |
|-------|---------|-------------|
| **source-first** | `/source-first` | Answer technical questions exclusively from primary sources (official docs, changelogs, source code). Never rely on memorized knowledge. |
| **github-kb** | `/github-kb <cmd>` | Local GitHub repo management + social media (Xiaohongshu, Twitter/X) trending project discovery. |

### ML Experiments

| Skill | Command | Description |
|-------|---------|-------------|
| **experiment-runner** | `/experiment-runner` | Full ML experiment lifecycle: intent alignment, dry-run validation, auto-launch, checkpoint recovery, and cron-based self-healing monitoring. |

### Infrastructure

| Skill | Command | Description |
|-------|---------|-------------|
| **claw-guru** | `/claw-guru` | OpenClaw live support — config debugging, gateway troubleshooting, channel setup. Always verifies against live docs. |

## Workflow Example

```
/interview          # Clarify requirements (interactive Q&A)
/spawn              # Decompose and dispatch parallel agents
... (work happens)
/codex              # Cross-review with Codex
/save-session       # Save progress before ending
```

## License

MIT
