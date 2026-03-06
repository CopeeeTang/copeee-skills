# GitHub Knowledge Base - Setup Guide

## Quick Start

1. **Initialize knowledge base directory:**
   ```bash
   mkdir -p ~/github
   ```

2. **Set environment variables** (add to `~/.zshrc` or `~/.bashrc`):
   ```bash
   # Required for Twitter/X fetching
   export JINA_API_KEY="your_jina_api_key"

   # Optional: VLM for Xiaohongshu image analysis (pick one)
   export ZZZ_API_KEY="your_zhizengzeng_key"      # 智增增 (优先)
   export ZHIPU_API_KEY="your_zhipu_glm4v_key"    # 智谱 GLM-4V (备选，有内置测试 Key)
   ```

3. **Verify rednote-mind-mcp is configured** in `~/.claude.json`:
   ```json
   {
     "mcpServers": {
       "rednote": {
         "command": "npx",
         "args": ["-y", "rednote-mind-mcp"]
       }
     }
   }
   ```

4. **First-time Xiaohongshu login:**
   ```bash
   npx rednote-mind-mcp init
   ```
   Or in Claude Code: `请登录小红书`

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `JINA_API_KEY` | For Twitter | Jina.ai Reader API key ([get free key](https://jina.ai/)) |
| `ZZZ_API_KEY` | Optional | 智增增 VLM API key (优先使用) |
| `ZHIPU_API_KEY` | Optional | 智谱 GLM-4V API key (内置测试 key 可用) |

## Data Storage Locations

| Data | Path |
|------|------|
| Knowledge base | `~/github/` (configurable) |
| KB index | `~/github/CLAUDE.md` |
| Xiaohongshu cookies | `~/.mcp/rednote/cookies.json` |
| Downloaded images | `~/.mcp/rednote/images/` |

## Verify Installation

```bash
# Check gh CLI
gh auth status

# Check Jina API
curl -s "https://r.jina.ai/https://x.com" -H "Authorization: Bearer $JINA_API_KEY" | head -20

# Check rednote MCP
npx rednote-mind-mcp --version
```

## Troubleshooting

### Xiaohongshu login expired
```bash
rm ~/.mcp/rednote/cookies.json
npx rednote-mind-mcp init
```

### Twitter fetch fails
- Verify `JINA_API_KEY` is set: `echo $JINA_API_KEY`
- Check API status: https://jina.ai/status

### VLM analysis not working
- Check if either `ZZZ_API_KEY` or `ZHIPU_API_KEY` is set
- 智谱 GLM-4V has a built-in test key, should work out of box
