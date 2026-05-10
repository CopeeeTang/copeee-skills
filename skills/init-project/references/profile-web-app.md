# Profile: Web App / 后端 API

## 信号识别

满足任一即匹配 Web app profile：
- `package.json` 含 `next` / `react` / `vue` / `svelte` / `express` / `fastify` / `nestjs` / `remix`
- `pyproject.toml` 含 `fastapi` / `flask` / `django`
- `go.mod` 含 `gin` / `echo` / `fiber`
- 顶层有 `pages/`, `app/`, `src/components/`, `routes/`, `api/`
- 有 `next.config.*`, `vite.config.*`, `webpack.config.*`, `tailwind.config.*`
- README 提到 "API", "endpoint", "route"

---

## Phase 4 额外提问

```
WEB-Q1: 前端框架？
  [a] React (vanilla / with vite)
  [b] Next.js
  [c] Vue / Nuxt
  [d] Svelte / SvelteKit
  [e] 仅后端 (no frontend)

WEB-Q2: 后端运行时？
  [a] Node.js (Express / Fastify / Nest)
  [b] Python (FastAPI / Flask / Django)
  [c] Go
  [d] Rust
  [e] 仅前端 (SPA + 第三方 API)

WEB-Q3: 数据库？
  [a] Postgres
  [b] SQLite
  [c] Mongo / DynamoDB / Firestore
  [d] Supabase / Planetscale (managed)
  [e] 无数据库

WEB-Q4: 浏览器/E2E 测试？
  [a] Playwright
  [b] Cypress
  [c] Puppeteer
  [d] 无 E2E 测试
```

---

## 推荐 plugins（enabled）

```json
{
  "context7@claude-plugins-official": true,         // 框架文档（React / Next / Vue 全覆盖）
  "frontend-design@claude-plugins-official": true,  // UI 组件设计
  "code-simplifier@claude-plugins-official": true,
  "code-review@claude-plugins-official": true,
  "superpowers@superpowers-marketplace": true,
  "claude-md-management@claude-plugins-official": true
}
```

**视答案条件加**：
- WEB-Q4 选 Playwright → 装 `playwright` MCP server
- WEB-Q3 选 Postgres / Supabase → 装对应 MCP
- WEB-Q1 选 Next.js → context7 + ralph-loop（迭代调试）

---

## 推荐 skills

| Skill | 来源 | 用途 |
|-------|------|------|
| `superpowers:brainstorming` | superpowers | 新 feature 设计前 |
| `superpowers:test-driven-development` | superpowers | 写新组件/路由前 |
| `superpowers:verification-before-completion` | superpowers | 提 PR 前 |
| `frontend-design:frontend-design` | frontend-design plugin | 新组件/页面 |
| `claude-md-management:revise-claude-md` | plugin | 项目演化时更新指令 |

---

## 推荐 .claude/commands/

```
.claude/commands/
├── dev.md           # 启动 dev server（npm run dev）
├── test.md          # 跑测试（含 lint + typecheck + unit）
└── e2e.md           # 跑 Playwright（如装了）
```

例（`dev.md`）：
```markdown
---
description: "Start the development server."
---

Start the dev server in the background and report the URL.

Use the script: `npm run dev` (or yarn / pnpm based on lockfile).
Verify the server is reachable at http://localhost:3000 (or detected port).
Stream first 50 lines of stdout, then disown.
```

---

## 推荐 hooks（关键）

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {"type": "command", "command": "bash -c 'F=\"$CLAUDE_FILE_PATHS\"; case $F in *.ts|*.tsx|*.js|*.jsx) npx prettier --write \"$F\" 2>/dev/null;; esac'"}
      ]
    }
  ]
}
```

**TypeScript 项目额外加**：
```json
{
  "matcher": "Edit",
  "hooks": [
    {"type": "command", "command": "bash -c 'npx tsc --noEmit 2>&1 | head -20 || true'"}
  ]
}
```

---

## 推荐 .claude/settings.json 关键字段

```json
{
  "permissions": {
    "defaultMode": "dontAsk",
    "allow": [
      "Bash(npm *)",
      "Bash(yarn *)",
      "Bash(pnpm *)",
      "Bash(npx *)",
      "Bash(curl http://localhost:*)"
    ],
    "deny": [
      "Edit(.env)",
      "Edit(.env.local)",
      "Edit(.env.production)",
      "Edit(prisma/migrations/**)",
      "Edit(supabase/migrations/**)",
      "Bash(npm publish*)",
      "Bash(yarn publish*)"
    ]
  }
}
```

---

## CLAUDE.md 模板片段（Web app 专用段落）

```markdown
## Stack
- Frontend: <user-filled, e.g. Next.js 15 + React 19 + Tailwind>
- Backend: <user-filled>
- Database: <user-filled>
- Tests: <user-filled, e.g. vitest + Playwright>

## Dev workflow
- `npm run dev` (or /dev command) — start dev server
- `npm test` — vitest unit tests
- `npm run e2e` — Playwright (only after manual seed)

## Code conventions（人工约定，lint 管不到的）
- <user-filled, e.g. "API routes 必须 throw 而不是 return error">
- <user-filled, e.g. "禁止在 lib/ 下加新依赖，只能用 app/ 现有">

## ⚠️ IMPORTANT
- 永远不要 git commit `.env*` 文件
- 永远不要直接编辑 `migrations/` ——先生成 migration

## 部署
- <user-filled, e.g. Vercel auto-deploy on main / Docker → ECS>
```

---

## 反模式（Web 项目特有）

- **不要让 Claude 跑 `npm install` 改 lockfile** 不经确认 → 写进 settings 要求审核
- **不要把 prettier / eslint / tsc 写进 CLAUDE.md prose** → 全部用 hook
- **不要装 frontend-design 给纯后端项目**（精确按 Q1 答案决定）
- **不要让 Claude 直接跑 migration**（DBA 边界）→ permissions.deny 守住
