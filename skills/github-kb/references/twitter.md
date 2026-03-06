# Twitter/X Integration

Fetch Twitter/X post content using Jina.ai API.

## Prerequisites

Set environment variable:
```bash
export JINA_API_KEY="your_api_key_here"
```

Get key from https://jina.ai/ (free tier available).

> **Note:** `JINA_API_KEY` is also used for general web content fetching. Consider it a core API key for this skill.

## Quick Usage

**Single tweet:**
```bash
curl "https://r.jina.ai/https://x.com/USER/status/TWEET_ID" \
  -H "Authorization: Bearer ${JINA_API_KEY}"
```

**Multiple tweets:**
```bash
scripts/fetch_tweets.sh url1 url2 url3
```

## What Gets Returned

- **Title**: Post author and content preview
- **URL Source**: Original tweet link
- **Published Time**: GMT timestamp
- **Markdown Content**: Full post text with media descriptions

## Bundled Scripts

### fetch_tweet.py
```bash
python scripts/fetch_tweet.py https://x.com/user/status/123 output.md
```

### fetch_tweets.sh
```bash
scripts/fetch_tweets.sh \
  "https://x.com/user/status/123" \
  "https://x.com/user/status/456"
```

## Supported URL Formats

- `https://x.com/USER/status/ID`
- `https://twitter.com/USER/status/ID`
- Redirects work automatically
