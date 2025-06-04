#!/bin/sh
set -e

# Configuration
REPO_URL="${REPO_URL:-https://git.vezpi.me/Vezpi/blog.git}"
URL="${URL:-blog.vezpi.com}"
BRANCH="${BRANCH:-preview}"
CLONE_DIR="${CLONE_DIR:-/blog}"
DRAFTS=""

# Add drafts for preview
if [ $BRANCH == "preview" ]; then
  echo "- Adding draft pages for the site"
  DRAFTS="--buildDrafts"
else
  echo "BRANCH= $BRANCH"
fi

# Clone repo
echo "- Cloning $REPO_URL (branch: $BRANCH)..."
git clone --depth 1 --recurse-submodules --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR"

# Generate static files with hugo
echo "- Building site with Hugo v$HUGO_VERSION in $HUGO_DEST..."
hugo --source "$CLONE_DIR" --destination "$HUGO_DEST" --baseURL="https://${URL}" "$DRAFTS" --logLevel info --cleanDestinationDir --gc --panicOnWarning --printI18nWarnings

# Start nginx
echo "- Starting Nginx..."
exec nginx -g 'daemon off;'