---
title: Automated Blog Deployment featuring Obsidian, Hugo and Gitea Actions
date: 2025-05-02
draft: true
tags:
---
Over the past few days, I set up an automated pipeline to build and deploy my blog using **Gitea Actions**. This post explains how it works and the design decisions behind it.

## 🧠 Goals

- Write blog posts in my [Obsidian](https://obsidian.md) vault
- Automatically detect changes in the `Blog/` folder
- Sync changes to a separate **blog repository**
- Let the blog repository handle **site generation and deployment**
- Use Hugo as the static site generator, with version updates handled automatically

---

## 🔁 Workflow Overview

Here's the flow:

1. **Edit Blog Content** in the `Blog/` folder of my Obsidian vault.
2. **Obsidian Repo Workflow** (via Gitea Actions):
   - Detects changes in the `Blog/` folder.
   - Clones the blog repository using a secure token.
   - Syncs content from the Obsidian vault to the blog repository.
   - Commits and pushes changes.
3. **Blog Repo Workflow** (also using Gitea Actions):
   - Pulls the latest Hugo release version.
   - Compares it with the current version.
   - Downloads it if necessary.
   - Builds the blog using the new version.
   - If the build fails, tries the previous version.
   - Pushes the updated static site to the target branch (e.g., `gh-pages` or `public`)

---

## ⚙️ Key Implementation Details

### 🔐 Secure Token Usage

A **Gitea secret** is used to securely clone the blog repository. In the Obsidian repo workflow:

    env:
      TOKEN: ${{ secrets.BLOG_DEPLOY_TOKEN }}
    run: |
      git clone https://${TOKEN}@git.example.com/user/blog.git /appli/data/blog

This avoids exposing any credentials in code or logs.

### 📦 Hugo Version Check

The workflow checks for the latest Hugo release from GitHub:

    latest_version=$(curl -s https://api.github.com/repos/gohugoio/hugo/releases/latest | jq -r .tag_name)

If it's newer than the currently used version, it downloads and installs it in `/appli/data/blog/bin`.

### 🔄 Sync from Obsidian to Blog Repo

Using `rsync -ah --delete` ensures the content in `/Blog` is mirrored properly:

    rsync -ah --delete Blog/ /appli/data/blog/content/

### 🧪 Fallback on Hugo Failure

If building the site with the new version fails, the old binary is used as a fallback, ensuring the site doesn't break unexpectedly.

---

## 🚀 Results

This setup gives me:

- A **clean separation** between content editing (Obsidian) and publishing (Blog repo).
- Automated static site builds without needing GitHub Actions or external CI.
- Full control over the Hugo version, testing, and rollback.

---

## 📍 Next Steps

- Add preview and validation steps before committing
- Monitor Hugo releases for breaking changes
- Expand workflows to manage themes and assets

---

If you're self-hosting Gitea and want to build your own blog workflow, I hope this gives you a solid starting point. Feel free to reach out with questions!