---
name: source-first
description: Use when user runs "/source-first", asks to "check official docs", "look up the source", "read the original blog", or wants authoritative first-party answers instead of second-hand summaries. Covers any technology question where primary sources (official docs, blogs, source code, changelogs) exist.
---

# Source-First Research

Answer technical questions exclusively from primary sources. Never rely on memorized knowledge or second-hand summaries when this skill is active.

## Source Priority

Always follow this hierarchy — stop at the first level that answers the question:

1. **Official documentation** — resolve via context7, then fetch
2. **Official blog posts / changelogs** — fetch the URL with defuddle
3. **GitHub source code / README / releases** — read via GitHub MCP or `gh` CLI
4. **Web search as last resort** — tavily/web search, but only for locating a primary URL to then fetch directly

Never present search engine snippets as the answer. Search is only for **finding the primary URL**, then fetch and read the actual page.

## Tool Selection

| Source type | Tool | When to use |
|-------------|------|-------------|
| Library/framework docs | `context7` (`resolve-library-id` then `query-docs`) | Question about a specific library's API, usage, or features |
| Blog post / announcement | `defuddle` (obsidian skill) | User provides URL, or you locate an official blog URL |
| Web page (fallback) | `WebFetch` | When defuddle is unavailable or fails |
| GitHub repo / source | `gh` CLI or GitHub MCP tools | Source code, README, releases, issues |
| Locating URLs | `tavily-search` or `WebSearch` | Only to find the official URL, then fetch it with the tools above |

### context7 workflow

```
1. resolve-library-id with library name
2. query-docs with the resolved ID and the specific question
3. Extract relevant sections from the response
```

### defuddle workflow (preferred for web pages)

```
1. Obtain the official URL (from user, or from a search)
2. Use defuddle to extract clean markdown content
3. If defuddle fails, fall back to WebFetch
```

### GitHub workflow

```
1. gh repo view owner/repo (overview)
2. gh api repos/owner/repo/releases/latest (changelogs)
3. Read specific files: gh api repos/owner/repo/contents/path
```

## Output Format

Structure every response as:

```markdown
## Source

[URL or source identifier]
Retrieved: [timestamp or "from context7 docs"]

## Key Excerpt

> [Direct quote or extracted content from the primary source]
> [Include enough context to be self-contained]

## Analysis

[Your interpretation, summary, and answer to the user's question]
[Connect multiple sources if needed]
[Flag if the source is dated or potentially outdated]
```

## Rules

- **No memory-based answers.** If you cannot find a primary source, say so explicitly rather than answering from training data.
- **Quote before interpreting.** Always show the original text first, then your analysis.
- **Attribute everything.** Every claim must trace back to a specific source with a URL or file path.
- **Prefer narrow fetches.** Use context7 topic queries or grep-style searches over fetching entire pages when possible.
- **Admit gaps.** If the primary source doesn't fully answer the question, state what it covers and what remains unclear.
