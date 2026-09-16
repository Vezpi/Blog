#!/bin/sh
set -e

# Configuration
REPO_URL="${REPO_URL:-https://git.vezpi.com/Vezpi/blog.git}"
URL="${URL:-blog.vezpi.com}"
BRANCH="${BRANCH:-preview}"
BLOG_DIR="${BLOG_DIR:-/blog}"
HUGO_RESOURCES_DIR="${HUGO_RESOURCES_DIR:-/hugo-resources}"
DRAFTS=""

# Add drafts for preview
if [ "$BRANCH" = "preview" ]; then
  echo "- Adding draft pages to be generated"
  DRAFTS="--buildDrafts --buildFuture"
fi

# Clean blog dir
rm -rf "$BLOG_DIR"

# Clone repo
echo "- Cloning $REPO_URL (branch: $BRANCH)..."
git clone --recurse-submodules --branch "$BRANCH" "$REPO_URL" "$BLOG_DIR"

# Restore persistent Hugo resources cache
rm -rf "$BLOG_DIR/resources"
ln -s "$HUGO_RESOURCES_DIR" "$BLOG_DIR/resources"

# Generate static files with hugo
echo "- Building site with Hugo v$HUGO_VERSION in $HUGO_DEST..."
hugo --source "$BLOG_DIR" \
  --destination "$HUGO_DEST" \
  --baseURL="https://${URL}" \
  ${DRAFTS} \
  --logLevel info \
  --cleanDestinationDir \
  --gc \
  --panicOnWarning \
  --printI18nWarnings

# Start nginx
echo "- Starting Nginx..."
exec nginx -g 'daemon off;'