# copeee-skills

Productivity skills for [Claude Code](https://claude.com/claude-code).

## Installation

```bash
/plugin install github:CopeeeTang/copeee-skills
```

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| **interview-mode** | `/interview` | Structured requirements clarification before planning. Ask the right questions, produce actionable summaries. |
| **spawn** | `/spawn <task>` | Task execution topology router. Analyzes dependencies and routes to optimal parallel/sequential execution mode. |
| **save-session** | `/save-session [project]` | Save session action history before context compaction. Extracts key decisions, data, and next steps. |
| **github-kb** | `/github-kb <cmd>` | Local GitHub repo management + social media (Xiaohongshu, Twitter/X) trending project discovery. |
| **code-simplifier** | `/simplify` | Refine recently modified code for clarity and maintainability while preserving functionality. |

## Workflow Example

```
/interview          # Clarify requirements
/spawn              # Decompose and dispatch parallel agents
... (work happens)
/save-session       # Save progress before ending
```

## License

MIT
