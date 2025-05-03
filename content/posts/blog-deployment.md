---
title: Blog Deployment featuring Obsidian, Hugo and Gitea Actions
date: 2025-05-02
draft: true
tags:
---
I always wanted to share my own experiences to give others ideas or help them on their projects.

I'm constantly tinkering in my homelab, trying new tools and workflows. Instead of keeping all these experiments in private notes, I decided to create a blog where I can document and publish them easily.

I wanted the entire process to be automated, self-hosted, and integrated into the tools I already use daily.

## 🔧 Tools
### Obsidian

Before I was using Notion, but some months ago I switched to [Obsidian](https://obsidian.md/). It's a markdown-based note-taking app that stores everything locally, which gives me more flexibility and control.

To sync my notes between devices, I use the [Obsidian Git plugin](https://github.com/denolehov/obsidian-git), which commits changes to a Git repository hosted on my self-hosted Gitea instance.

This setup not only allows for versioned backups of all my notes but also opens the door to automation.

### Gitea

[Gitea](https://gitea.io/) is a self-hosted Git service similar to GitHub, but lightweight and easy to maintain. I host my personal repositories there, including my Obsidian vault and my blog.

Gitea now supports [Gitea Actions](https://docs.gitea.com/usage/actions/overview), a CI/CD pipeline mechanism compatible with GitHub Actions syntax. 

To run those workflows, I installed a [Gitea runner](https://gitea.com/gitea/act_runner) on my server, allowing me to create an automated workflow triggered when I update content in my notes, which then builds and deploys my blog.

### Hugo

[Hugo](https://gohugo.io/) is a fast and flexible static site generator written in Go. It’s perfect for generating content from Markdown files. Hugo is highly customizable, supports themes, and can generate a complete website in seconds. It’s ideal for a blog based on Obsidian notes, and it works beautifully in CI/CD pipelines due to its speed and simplicity.

## 🔁 Workflow

The idea is simple:

1. I write blog content in my Obsidian vault, under a specific `Blog` folder.
2. When I push updates to that folder, a first Gitea Action is triggered.
3. The first action syncs the updated blog content to a separate [blog repository](https://git.vezpi.me/Vezpi/blog).
4. In the blog repository, another Gitea Action is triggered.
5. The second Gitea Action generates the static web pages while upgrading Hugo if needed
6. The blog is now updated.

This way, I never need to manually copy files or trigger deployments. Everything flows from writing markdown in Obsidian to having a fully deployed website.

## ⚙️Implementation

### Step 1: Obsidian Vault Setup

In my Obsidian vault, I created a `Blog` folder that contains my blog posts in Markdown. Each post includes Hugo frontmatter (`title`, `date`, `draft`, etc.). The Git plugin is configured to commit and push automatically when I make changes to the Gitea repository.

### Step 2: Spin up Gitea Runner

The Obsidian vault is a private Git repository self-hosted in Gitea. I use docker compose to run this instance, to enable the Gitea Actions, I added the Gitea runner in the stack
```yaml
  runner:
    image: gitea/act_runner:latest
    container_name: gitea_runner
    restart: on-failure
    environment:
      - GITEA_INSTANCE_URL=https://git.vezpi.me
      - GITEA_RUNNER_REGISTRATION_TOKEN=${GITEA_RUNNER_REGISTRATION_TOKEN}$
      - GITEA_RUNNER_NAME=self-hosted
      - GITEA_RUNNER_LABELS=ubuntu:docker://node:lts,alpine:docker://node:lts-alpine
      - CONFIG_FILE=/data/config.yml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /appli/data/gitea/runner:/data
      - /appli:/appli
    networks:
      - backend
    depends_on:
      - server
```

The `config.yml` only contains the allowed volume to bind in the containers
```yaml
container:
  valid_volumes:
    - /appli*
```

The runner appears in the `Administration Area`, under `Actions`>`Runners`. To obtain the registration token, click on the `Create new Runner` button
![[Pasted image 20250502230954.png]]

### Step 3: Set up Gitea Actions for Obsidian Repository

First I enabled the Gitea Actions, this is disabled by default, tick the box `Enable Repository Actions`  in the settings for that repository

I created a new PAT (Personal Access Token) with RW permission on the repositories
![[Pasted image 20250501235521.png]]

I added this token as secret `REPO_TOKEN` in the repository
![[Pasted image 20250501235427.png]]

I needed to create the workflow that will spin-up a container and do the following:
- When I push new/updated files in the `Blog` folder
- Install `rsync`
- Checkout the current repository (Obsidian vault)
- Clone the blog repository
- Transfer blog content from Obsidian
- Commit the change to the blog repository

`.gitea/workflows/sync_blog.yml`
```yaml
name: Synchronize content with the blog repo
on:
  push:
    paths:
      - 'Blog/**' 

jobs:
  Sync:
    runs-on: ubuntu
    steps:
      - name: Install prerequisites
        run: apt update && apt install -y rsync
        
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Clone the blog repository
        run: git clone https://${{ secrets.REPO_TOKEN }}@git.vezpi.me/Vezpi/blog.git 

      - name: Transfer blog content from Obsidian
        run: rsync -av --delete Blog/ blog/content

      - name: Commit the change to the blog repository
        run: |
          cd blog
          git config --global user.name "Gitea Actions"
          git config --global user.email "actions@local"
          git config --global --add safe.directory /appli/data/blog
          git add .
          git commit -m "Auto-update blog content from Obsidian: $(date '+%F %T')" || echo "Nothing to commit"
          git push -u origin main
```

### Step 4: Gitea Actions for Blog Repository

The blog repository contains the full Hugo site, including the synced content and theme.

Its workflow:
- Install `jq`
- Checkout the blog repository
- Check if the Hugo version is up-to-date. If not, it downloads the latest release and replaces the old binary.
- Build the static website using Hugo.

`.gitea/workflows/deploy_blog.yml`
```yaml
name: Deploy
on: [push]
jobs:
  Deploy:
    runs-on: ubuntu
    env:
      BLOG_FOLDER: /blog
    container:
      volumes:
        - /appli/data/blog:/blog
    steps:
      - name: Install prerequisites
        run: apt update && apt install -y jq
        
      - name: Check out repository
        run: |
          cd ${BLOG_FOLDER}
          git config --global user.name "Gitea Actions"
          git config --global user.email "actions@local"
          git config --global --add safe.directory ${BLOG_FOLDER}
          git pull

      - name: Get current Hugo version
        run: echo "current_version=$(${BLOG_FOLDER}/bin/hugo version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')" | tee -a $GITEA_ENV

      - name: Verify latest Hugo version
        run: echo "latest_version=$(curl -s https://api.github.com/repos/gohugoio/hugo/releases/latest | jq -r .tag_name)" | tee -a $GITEA_ENV

      - name: Download latest Hugo version
        if: env.current_version != env.latest_version
        run: |
          curl -L https://github.com/gohugoio/hugo/releases/download/$latest_version/hugo_extended_${latest_version#v}_Linux-64bit.tar.gz -o hugo.tar.gz
          tar -xzvf hugo.tar.gz -C ${BLOG_FOLDER}/bin/

      - name: Generate the static files with Hugo
        run: |
          rm -f ${BLOG_FOLDER}/content/posts/template.md
          ${BLOG_FOLDER}/bin/hugo -D -b https://blog-dev.vezpi.me -s ${BLOG_FOLDER} -d ${BLOG_FOLDER}/private
          ${BLOG_FOLDER}/bin/hugo -s ${BLOG_FOLDER} -d ${BLOG_FOLDER}/public

```

## 🚀 Results

This workflow gives me the best of both worlds: I can focus on writing in Obsidian, and my infrastructure takes care of the rest — from syncing and building to publishing the blog automatically.

