#!/bin/sh
set -e

# Configuration
REPO_URL="${REPO_URL:-https://git.vezpi.me/Vezpi/blog.git}"
BRANCH="${BRANCH:-preview}"
CLONE_DIR="${CLONE_DIR:-/blog}"

echo "- Cloning $REPO_URL (branch: $BRANCH)..."
git clone --depth 1 --recurse-submodules --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR"

echo "- Building site with Hugo v$HUGO_VERSION in $HUGO_DEST..."
hugo --source "$CLONE_DIR" --destination "$HUGO_DEST" --logLevel info --cleanDestinationDir --gc --panicOnWarning --printI18nWarnings

echo "- Starting Nginx..."
exec nginx -g 'daemon off;'