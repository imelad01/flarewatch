#!/usr/bin/env bash
set -e

echo "=== FlareWatch Upstream Sync ==="

if ! git remote | grep -q "^upstream$"; then
  echo "Adding upstream remote https://github.com/saminnet/flarewatch.git..."
  git remote add upstream https://github.com/saminnet/flarewatch.git
fi

STASHED=false
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "Stashing uncommitted local changes..."
  git stash push -m "flarewatch-autostash-$(date +%Y%m%d%H%M%S)"
  STASHED=true
fi

echo "Fetching latest changes from upstream..."
git fetch upstream --tags

CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="main"
fi

echo "Merging upstream/main into $CURRENT_BRANCH..."
if ! git merge upstream/main -m "Merge upstream updates into $CURRENT_BRANCH"; then
  echo "Merge conflicts detected. Preserving local user configuration files..."
  for f in $(git diff --name-only --diff-filter=U); do
    if [[ "$f" == packages/config/src/* ]]; then
      echo "Preserving local config: $f"
      git checkout --ours "$f"
      git add "$f"
    fi
  done
  if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
    git commit -m "Resolve merge conflicts keeping local config"
    echo "Resolved conflicts preserving local configs!"
  else
    echo "Please resolve remaining conflicts manually."
  fi
fi

if [ "$STASHED" = true ]; then
  echo "Restoring stashed changes..."
  git stash pop
fi

KV_ID="2240fb69338b431ea0e7ed752d01ce47"
WRANGLER_FILE="apps/status-page/wrangler.jsonc"
if [ -f "$WRANGLER_FILE" ]; then
  if grep -q "__FLAREWATCH_STATE_KV_NAMESPACE_ID__" "$WRANGLER_FILE"; then
    echo "Re-applying KV namespace ID..."
    sed -i "s/__FLAREWATCH_STATE_KV_NAMESPACE_ID__/$KV_ID/g" "$WRANGLER_FILE"
  fi
fi

echo "Ensuring packages are up to date..."
pnpm install

echo "✓ Upstream sync complete!"
echo "Deploy directly with: pnpm run deploy:all"
