# Xiaohongshu (小红书) Integration

## Available MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__rednote__check_login_status` | 检查登录状态 |
| `mcp__rednote__login` | 登录（打开浏览器扫码） |
| `mcp__rednote__search_notes_by_keyword` | 关键词搜索笔记 |
| `mcp__rednote__get_favorites_list` | 获取收藏夹列表（基本信息） |
| `mcp__rednote__get_note_content` | 获取笔记完整内容 |
| `mcp__rednote__get_batch_notes_from_favorites` | 批量获取收藏内容 |
| `mcp__rednote__download_note_images` | 下载笔记图片到本地 |

## Workflows

### 1. Keyword Search
```
Check login → search_notes_by_keyword → get_note_content (optional) → Analyze
```

**Parameters:**
```json
{
  "keyword": "搜索关键词",
  "limit": 10,
  "sortType": "general | popular | latest"
}
```

### 2. Favorites Analysis

**Quick preview (titles only):**
```json
{ "limit": 50 }
```

**Full content with images:**
```json
{
  "limit": 15,
  "includeImages": true
}
```

### 3. Single Note Content
```json
{
  "noteUrl": "https://www.xiaohongshu.com/explore/xxx?xsec_token=...",
  "includeImages": true,
  "includeData": true,
  "imageMode": "original | vlm",
  "compressImages": true,
  "imageQuality": 65,
  "maxImageSize": 1600
}
```

**Important:** Always use URLs with `xsec_token` from search/favorites results.

## Image Processing Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `original` | 返回压缩后的 Base64 图片 | 需要查看原图 |
| `vlm` | VLM 分析图片，返回文字描述 | 需要理解图片内容、OCR |

### VLM Provider Priority
1. **智增增** (ZZZ_API_KEY) - 优先使用
2. **智谱 GLM-4V** (ZHIPU_API_KEY) - 备选，内置测试 Key

## Performance Tips

| Scenario | Settings | Speed |
|----------|----------|-------|
| Text-only | `includeImages: false` | Fast |
| Compressed images | `includeImages: true, imageMode: "original"` | Medium |
| VLM analysis | `imageMode: "vlm"` | Slower |

**Batch limits:** Quick 5-10, Standard 10-15, Max 20

**Image compression defaults:**
- Quality: 65 (50-95)
- Max size: 1600px (960-2560)

## Output Format

```markdown
## Research: [Topic]

**Time**: YYYY-MM-DD HH:mm
**Results**: N notes

### Key Findings

| Title | Author | Engagement | Summary |
|-------|--------|------------|---------|
| [Note](url) | Author | 1.2K | ... |

### VLM Analysis (if imageMode=vlm)
- Image 1: [description]
- Image 2: [description]
```

## Data Storage

- **Cookies**: `~/.mcp/rednote/cookies.json`
- **Downloaded images**: `~/.mcp/rednote/images/{noteId}/`
