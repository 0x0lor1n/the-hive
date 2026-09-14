#!/usr/bin/env bash

# Read input from Claude Code
input=$(cat)

# Parse JSON to extract model and directory
MODEL=$(echo "$input" | jq -r ".model.display_name")
DIR=$(echo "$input" | jq -r ".workspace.current_dir")

# Get git branch information if in a git repo
BRANCH=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

  # Count changes
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
  if [ $CHANGES -gt 0 ]; then
    BRANCH="$BRANCH ($CHANGES)"
  fi
fi

# Output formatted statusline
echo "[$MODEL] 📁 ${DIR##*/}$BRANCH | 🕐 $(date +%H:%M)"
