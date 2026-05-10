#!/usr/bin/env bash
# sync-skills.sh — Sync skills between ~/.claude/skills/ (source of truth)
#                  and copeee-skills plugin marketplace.
#
# Usage:
#   sync-skills.sh push [skill_name ...]   # local → copeee-skills (default)
#   sync-skills.sh pull [skill_name ...]   # copeee-skills → local
#   sync-skills.sh diff [skill_name ...]   # show drift without copying
#   sync-skills.sh list                    # list skills present in both
#
# No skill args = operate on all skills present in both locations.

set -euo pipefail

LOCAL="$HOME/.claude/skills"
PLUGIN="$HOME/.claude/plugins/marketplaces/copeee-skills/skills"

if [[ ! -d "$LOCAL" ]]; then
  echo "ERROR: $LOCAL not found" >&2
  exit 1
fi
if [[ ! -d "$PLUGIN" ]]; then
  echo "ERROR: $PLUGIN not found" >&2
  exit 1
fi

cmd="${1:-push}"
shift || true

# Resolve skill list: explicit args, else intersection of both dirs
if [[ $# -gt 0 ]]; then
  SKILLS=("$@")
else
  mapfile -t SKILLS < <(comm -12 \
    <(ls -1 "$LOCAL" | sort) \
    <(ls -1 "$PLUGIN" | sort))
fi

case "$cmd" in
  list)
    printf '%s\n' "${SKILLS[@]}"
    ;;
  diff)
    for s in "${SKILLS[@]}"; do
      if [[ -f "$LOCAL/$s/SKILL.md" && -f "$PLUGIN/$s/SKILL.md" ]]; then
        if ! diff -q "$LOCAL/$s/SKILL.md" "$PLUGIN/$s/SKILL.md" > /dev/null; then
          echo "[DRIFT] $s"
          diff "$LOCAL/$s/SKILL.md" "$PLUGIN/$s/SKILL.md" | head -10
          echo "---"
        fi
      else
        echo "[MISSING] $s (local=$([[ -f $LOCAL/$s/SKILL.md ]] && echo y || echo n) plugin=$([[ -f $PLUGIN/$s/SKILL.md ]] && echo y || echo n))"
      fi
    done
    ;;
  push)
    for s in "${SKILLS[@]}"; do
      src="$LOCAL/$s"
      dst="$PLUGIN/$s"
      if [[ -L "$src" ]]; then
        echo "SKIP $s (symlinked; edits already propagate)" >&2
        continue
      fi
      if [[ ! -d "$src" ]]; then
        echo "SKIP $s (no local dir)" >&2
        continue
      fi
      mkdir -p "$dst"
      rsync -a --delete "$src/" "$dst/"
      echo "PUSH $s  →  $dst"
    done
    ;;
  pull)
    for s in "${SKILLS[@]}"; do
      src="$PLUGIN/$s"
      dst="$LOCAL/$s"
      if [[ -L "$dst" ]]; then
        echo "SKIP $s (symlinked; would corrupt symlink)" >&2
        continue
      fi
      if [[ ! -d "$src" ]]; then
        echo "SKIP $s (no plugin dir)" >&2
        continue
      fi
      mkdir -p "$dst"
      rsync -a --delete "$src/" "$dst/"
      echo "PULL $s  →  $dst"
    done
    ;;
  *)
    echo "Unknown command: $cmd"
    echo "Usage: sync-skills.sh {push|pull|diff|list} [skill_name ...]"
    exit 2
    ;;
esac
