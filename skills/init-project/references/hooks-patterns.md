# Hooks Patterns

> 写 settings.json 的 `hooks` 字段时按场景查这里。每条都是"必须每次发生 / 零容忍"的事。
>
> **核心原则**（Anthropic best-practices）：能交给 hook 的事，绝不写进 CLAUDE.md prose。

---

## 通用 4 个事件

| 事件 | 触发时机 | 典型用途 |
|------|----------|----------|
| `PreToolUse` | 工具调用前 | 阻止危险操作（rm -rf、edit secrets）|
| `PostToolUse` | 工具调用后 | format / lint / 语法检查 |
| `Stop` | 会话/turn 结束 | 清理临时文件 / 归档空 session |
| `SessionStart` | 会话启动 / compact 后 | 注入运行时上下文 |
| `PreCompact` | compact 前 | 备份当前 transcript |

---

## 模式库（按需复制）

### A. Python 语法保护（Edit/Write 后）

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {"type": "command", "command": "bash ~/.claude/hooks/python-syntax-check.sh"}
  ]
}
```

`python-syntax-check.sh` 内容（参考 `~/.claude/hooks/`，要点）：
```bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)
if [[ "$FILE_PATH" == *.py ]] && [[ "$FILE_PATH" != *__pycache__* ]] && [[ -f "$FILE_PATH" ]]; then
    python3 -m py_compile "$FILE_PATH" 2>&1 | head -5 || exit 1
fi
exit 0
```

### B. Prettier 自动格式化（JS/TS）

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; [[ $F == *.@(ts|tsx|js|jsx|json|md) ]] && npx prettier --write \"$F\" 2>/dev/null; true'"}
  ]
}
```

### C. Ruff format + lint（Python）

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; [[ $F == *.py ]] && (ruff format \"$F\" && ruff check --fix \"$F\") 2>/dev/null; true'"}
  ]
}
```

### D. TypeScript 类型检查（PostToolUse）

```json
{
  "matcher": "Edit",
  "hooks": [
    {"type": "command", "command": "bash -c 'npx tsc --noEmit 2>&1 | head -30 || true'"}
  ]
}
```

> 注意：`tsc --noEmit` 慢，大项目可能 5–10 秒；只在小项目用。

### E. Go fmt + vet

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; [[ $F == *.go ]] && (gofmt -w \"$F\" && go vet \"./$(dirname $F)/...\") 2>/dev/null; true'"}
  ]
}
```

### F. 阻止编辑敏感文件（PreToolUse）

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; if [[ $F =~ \\.(env|pem|key)$ || $F =~ secrets/ || $F =~ credentials/ ]]; then echo \"⛔ Refusing to edit sensitive file: $F\"; exit 1; fi'"}
  ]
}
```

> 这条是"硬阻止"：返回 exit 1 会让 Claude 拿到 stderr 内容并停止本次工具调用。

### G. 阻止编辑 migrations（DBA 边界）

```json
{
  "matcher": "Edit",
  "hooks": [
    {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; if [[ $F =~ /migrations/ ]]; then echo \"⛔ migrations/ is read-only — generate new migration via tool instead\"; exit 1; fi'"}
  ]
}
```

### H. 自动归档空 session（Stop）

```json
{
  "matcher": "",
  "hooks": [
    {"type": "command", "command": "bash ~/.claude/hooks/cleanup-empty-sessions.sh", "async": true}
  ]
}
```

### I. PreCompact 备份 transcript

```json
{
  "matcher": "",
  "hooks": [
    {"type": "command", "command": "bash ~/.claude/hooks/precompact-backup.sh", "async": true}
  ]
}
```

### J. SessionStart compact 后注入 context

```json
{
  "matcher": "compact",
  "hooks": [
    {"type": "command", "command": "bash ~/.claude/hooks/post-compact-inject.sh"}
  ]
}
```

`post-compact-inject.sh` 可以注入：上次 session 的关键决策、当前在跑的实验状态等。

---

## 反模式

1. **PostToolUse 跑超过 3 秒的事** → 严重拖慢交互，移到手动 command
2. **`pytest on save`** → 单测可能依赖 fixture/GPU，频繁失败干扰流程；用 `verification-before-completion` skill 在 commit 前跑
3. **同步 `npm install`** → 慢且会改 lockfile；如必须，加 `async: true`
4. **不限制 matcher** → `matcher: ""` 会对所有工具触发，PostToolUse 容易触发到 Read，浪费
5. **silent failure** → 关键 hook（语法检查、敏感文件阻止）必须 exit 1，不要 `|| true`
6. **PreToolUse 与 permissions.deny 重复** → 优先用 permissions.deny（更便宜）；hook 留给"动态条件"

---

## 调试技巧

```bash
# 手动模拟 hook 触发
echo '{"tool_input": {"file_path": "/tmp/test.py"}}' | bash ~/.claude/hooks/python-syntax-check.sh
echo "exit code: $?"
```

如果 hook 没生效：
1. 检查 `settings.json` 的 `hooks` 字段是否真的注册（不少 plugin 会覆盖）
2. 检查 hook 脚本是否 `chmod +x`
3. 用 stderr 调试：`echo "DEBUG: ..." >&2`
