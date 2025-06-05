---
slug: blog-deployment-ci-cd-pipeline-gitea-actions
title: Blog Deployment CI/CD Pipeline using Gitea Actions
description: How I secured the automated deployment of my self-hosted blog built with Hugo by setting up a CI/CD pipeline using Gitea Actions
date: 2025-06-05
draft: false
tags:
  - hugo
  - docker
  - ci-cd
  - gitea-actions
categories:
  - blog
---
## Intro

Now that my blog is live, I can’t really afford to break it with every single change. I did have a "preview" version of the blog that was generated alongside the public version, but it relied on the same content and only allowed me to view pages in draft mode.

Since the blog is automatically redeployed every time I modify content in Obsidian, as explained in [this article]({{< ref "post/2-blog-deployment-obisidan-hugo-gitea-actions" >}}), I don't always check whether the deployment failed or not. So I needed a way to protect it from my mistakes.

## Securing the Blog Deployment

Currently, my blog redeploys automatically on every change to the `main` branch of the [Git repository](https://git.vezpi.me/Vezpi/Blog) hosted on my **Gitea** instance, using a **Gitea Actions** workflow. Every change made in my **Obsidian** vault is automatically pushed to this branch.

![Workflow depuis l'écriture de notes sur Obsidian au Blog publié](img/obsidian-blog-gitea-actions-workflow.png)

### Create a New Branch

The first and easiest step was to create a new branch to receive these changes. So I created a `preview` branch in this repository and then updated the target branch in the workflow of my Obsidian Git repo.

![Create the preview branch from the main branch in Gitea](img/gitea-create-new-branch.png)

### Containerize the Blog

The blog generated with **Hugo**, is made of static files stored on the filesystem of my Virtual Machine `dockerVM`, and mounted as a volume in an `nginx` container.

I wanted to stop using mounted volumes and instead have the files generated at container startup, allowing me to run multiple independent instances of the blog.

So the second part was to build a **Docker** image that would:
1. Download the `hugo` binary.
2. Clone my blog’s Git repository.
3. Generate static pages with `hugo`.
4. Serve the web pages.

#### Build the Docker Image

A Docker container is based on an image, a template that already contains pre-executed instructions. When the container starts, it can then execute a new set of actions like running a server or script.

To build a Docker image, you need a file called `Dockerfile` which defines the actions to perform during the build. You can also add other files, like a script named `entrypoint.sh` that will be executed when the container starts.
```plaintext
docker/
├── Dockerfile
├── entrypoint.sh
└── nginx.conf
```

##### Dockerfile

In my case, I wanted the image, based on `nginx`, to include the web server configuration, the `hugo` binary, the ability to clone my Git repo, and to run a script on startup.
```Dockerfile
FROM nginx:stable

ARG HUGO_VERSION
ENV HUGO_VERSION=${HUGO_VERSION}
ENV HUGO_DEST=/usr/share/nginx/html

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Hugo
RUN curl -sSL https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz \
    | tar -xz -C /usr/local/bin hugo

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Nginx serves on port 80
EXPOSE 80

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
```

##### entrypoint.sh

By default, a `nginx` container simply starts the web server. But here I wanted it to first clone a specific branch of my blog repository, and then generate the static files using `hugo`.
```sh
#!/bin/sh
set -e

# Configuration
REPO_URL="${REPO_URL:-https://git.vezpi.me/Vezpi/blog.git}"
URL="${URL:-blog.vezpi.com}"
BRANCH="${BRANCH:-preview}"
CLONE_DIR="${CLONE_DIR:-/blog}"
DRAFTS=""

# Add drafts for preview
if [ "$BRANCH" = "preview" ]; then
  echo "- Adding draft pages to be generated"
  DRAFTS="--buildDrafts"
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
```

I’ve configured `hugo` to fail if any warning occurs, this way, the container won’t start if something goes wrong, making problems easier to catch.

I can now build my Docker image and pass the desired Hugo version as a build argument:
```bash
$ docker build --build-arg HUGO_VERSION=0.147.6 .
[+] Building 4.3s (11/11) FINISHED
 => [internal] load build definition from Dockerfile
 => => transferring dockerfile: 786B
 => [internal] load metadata for docker.io/library/nginx:stable
 => [internal] load .dockerignore
 => => transferring context: 2B
 => [1/6] FROM docker.io/library/nginx:stable@sha256:eaa7e36decc3421fc04478c586dfea0d931cebe47d5bc0b15d758a32ba51126f
 => [internal] load build context
 => => transferring context: 1.16kB
 => CACHED [2/6] RUN apt-get update && apt-get install -y     curl     git     ca-certificates     && rm -rf /var/lib/apt/lists/*
 => CACHED [3/6] RUN curl -sSL https://github.com/gohugoio/hugo/releases/download/v0.147.6/hugo_extended_0.147.6_Linux-64bit.tar.gz     | tar -xz -C /usr/local/bin hugo
 => [4/6] COPY entrypoint.sh /entrypoint.sh
 => [5/6] RUN chmod +x /entrypoint.sh
 => [6/6] COPY nginx.conf /etc/nginx/conf.d/default.conf 
 => exporting to image
 => => exporting layers
 => => writing image sha256:07cbeea704f3af16dc71a0890539776c87a95972a6c8f7d4fb24ea0eeab17032
```

✅ Now that I have my image, I can launch new instances of my blog without worrying about what's on the filesystem of my VM. I can also choose which Git branch the content should be generated from.

But I still can’t guarantee that these instances actually work, I need a way to **test** and then **deploy** them automatically.

To do that, I’m going to build a **CI/CD Pipeline**.

### CI/CD Pipeline

A CI/CD pipeline is a series of automated steps to test, build, and deploy an application. The **CI (Continuous Integration)** part checks that the code works with every change (e.g., by running tests), while the **CD (Continuous Deployment)** part automatically delivers the code to a test or production environment. This makes updates faster, more reliable, and more frequent.

There are different types of tools:
- **CI**: Jenkins, Travis CI, etc.
- **CD**: Argo CD, Flux CD, etc.
- **CI/CD**: GitLab CI/CD, GitHub Actions, etc.

In my case, I’m reusing **Gitea Actions**, which is very similar to GitHub Actions. It’s a CI/CD platform built into **Gitea**, using `YAML` workflow files stored in the Git repository.

Every time an event occurs, like a push or a tag), Gitea Actions automatically runs a set of steps (tests, build, deploy…) in an isolated environment based on Docker containers.

#### Gitea Runners

Gitea Actions workflows run through **Gitea Runners**. These fetch the jobs and execute them inside Docker containers, providing a clean and isolated environment for each step.

Since my blog instances are managed by `docker` (specifically `docker compose`), I needed the runner to interact with the Docker daemon on `dockerVM`. To achieve this, I added the `docker:cli` image to the runner catalog and gave it access to the VM’s `docker.socket`.

Here is the new configuration of my `runner` in my Gitea stack, also managed via `docker compose`:
```yaml
  runner:
    image: gitea/act_runner:latest
    container_name: gitea_runner
    restart: always
    environment:
      - GITEA_INSTANCE_URL=https://git.vezpi.me
      - GITEA_RUNNER_REGISTRATION_TOKEN=<token>
      - GITEA_RUNNER_NAME=self-hosted
      - GITEA_RUNNER_LABELS=ubuntu:docker://node:lts,alpine:docker://node:lts-alpine,docker:docker://docker:cli
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

#### Workflow

Previously, I had a simple workflow triggered on every push to the `main` branch of my blog’s Git repository. It did:
1. Checkout the Git repo into the `dockerVM` filesystem.
2. Download the latest Hugo binary if needed.
3. Generate the static blog files with Hugo.

Now, here’s what the new workflow does:
1. **Check-Rebuild**: Checks if a new Hugo version is available and if the `docker` folder in the repo has changed.
2. **Build**: If the previous job requires it, rebuilds the Docker image `vezpi-blog` and tags it with the Hugo version.
3. **Deploy-Staging**: Deploys the blog using the `preview` branch to a test URL via `docker compose`.
4. **Test-Staging**: Verifies that the `preview` version of the blog responds and works
5. **Merge**: Merges the `preview` branch into `main`.
6. **Deploy-Production**: Deploys the blog using the `main` branch (public version) with `docker compose`.
7. **Test-Production**: Verifies that the public blog is up and working.
8. **Clean**: Deletes the old Docker image.

Here’s an example of a deployment triggered by an automatic commit from **Obsidian**. You can see that the Docker image wasn’t rebuilt because no new Hugo version was available and the `docker` folder hadn’t changed, so the final `Clean` job wasn’t necessary either.

![Gitea Actions workflow for blog deployment](img/gitea-actions-deploy-blog-workflow.png)

#### Code

The workflow is written in `YAML` and must be located in the `.gitea/workflows/` folder of the Git repository.
```yaml
name: Blog Deployment

on:
  push:
    branches:
      - preview

env:
  DOCKER_IMAGE: vezpi-blog

jobs:
  Check-Rebuild:
    runs-on: docker
    defaults:
      run:
        shell: sh
    outputs:
      latest_hugo_version: ${{ steps.get_latest.outputs.version }}
      current_hugo_version: ${{ steps.get_current.outputs.version }}
      newer_version_available: ${{ steps.compare.outputs.version }}
      current_docker_image: ${{ steps.current_docker.outputs.image }}
      docker_folder_changed: ${{ steps.docker_folder.outputs.changed }}
    steps:
      - name: Checkout Repository
        run: git clone --branch preview https://${{ secrets.REPO_TOKEN }}@git.vezpi.me/Vezpi/blog.git .

      - name: Check Latest Hugo Version
        id: get_latest
        run: |
          apk add curl
          latest_version=$(curl -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep tag_name | sed -E 's/.*"v([^"]+)".*/\1/')
          echo "version=$latest_version" | tee -a $GITEA_OUTPUT

      - name: Check Current Hugo Version
        id: get_current
        run: |
          current_version=$(docker image ls ${DOCKER_IMAGE} --format '{{.Tag}}' | head -n1)
          echo "version=$current_version" | tee -a $GITEA_OUTPUT
      
      - name: Compare Current and Latest Hugo Versions
        id: compare
        run: |
          if [ "${{ steps.get_latest.outputs.version }}" != "${{ steps.get_current.outputs.version }}" ]; then
            new_version_available=true
            echo "New version available: ${{ steps.get_latest.outputs.version }}"
          else
            new_version_available=false
            echo "Current version is the latest: ${{ steps.get_latest.outputs.version }}"
          fi
          echo "version=$new_version_available" | tee -a $GITEA_OUTPUT

      - name: Get Current Docker Image ID
        id: current_docker
        run: |
          current_image=$(docker image ls ${DOCKER_IMAGE}:latest --format '{{.ID}}' | head -n1)
          echo "image=$current_image" | tee -a $GITEA_OUTPUT

      - name: Check Changes in the Docker Folder
        id: docker_folder
        run: |
          if git diff --name-only origin/main | grep -q '^docker/'; 
          then 
            docker_folder_changed=true
            echo "Change detected in the /docker folder"
          else 
            docker_folder_changed=false
            echo "No change in the /docker folder"
          fi
          echo "changed=$docker_folder_changed" | tee -a $GITEA_OUTPUT

  Build:
    needs: Check-Rebuild
    if: needs.Check-Rebuild.outputs.newer_version_available == 'true' || needs.Check-Rebuild.outputs.docker_folder_changed == 'true'
    runs-on: docker
    defaults:
      run:
        shell: sh
    steps:
      - name: Checkout Repository
        run: git clone --branch preview https://${{ secrets.REPO_TOKEN }}@git.vezpi.me/Vezpi/blog.git .

      - name: Build Docker Image
        run: |  
          cd docker
          docker build \
            --build-arg HUGO_VERSION=${{ needs.Check-Rebuild.outputs.latest_hugo_version }} \
            --tag ${DOCKER_IMAGE}:${{ needs.Check-Rebuild.outputs.latest_hugo_version }} \
            .
          docker tag ${DOCKER_IMAGE}:${{ needs.Check-Rebuild.outputs.latest_hugo_version }} ${DOCKER_IMAGE}:latest

  Deploy-Staging:
    needs: 
      - Check-Rebuild
      - Build
    if: always() && needs.Check-Rebuild.result == 'success' && (needs.Build.result == 'skipped' || needs.Build.result == 'success')
    runs-on: docker
    container:
      volumes:
        - /appli/docker/blog:/blog
    defaults:
      run:
        shell: sh
    env:
      CONTAINER_NAME: blog_staging
    steps:
      - name: Launch Blog Deployment
        run: |
          cd /blog
          docker compose down ${CONTAINER_NAME} 
          docker compose up -d ${CONTAINER_NAME}
          sleep 5
          echo "- Displaying container logs"
          docker compose logs ${CONTAINER_NAME}

  Test-Staging:
    needs: Deploy-Staging
    runs-on: ubuntu
    env:
      URL: "https://blog-dev.vezpi.com/en/"
    steps:
      - name: Check HTTP Response
        run: |
          code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
          echo "HTTP response code: $code"

          if [ "$code" -ne 200 ]; then
            echo "❌ Service is not healthy (HTTP $code)"
            exit 1
          else
            echo "✅ Service is healthy"
          fi

  Merge:
    needs: Test-Staging
    runs-on: ubuntu
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main
      
      - name: Merge preview Branch on main
        run: |
          git merge --ff-only origin/preview
          git push origin main

  Deploy-Production:
    needs: Merge
    runs-on: docker
    container:
      volumes:
        - /appli/docker/blog:/blog
    defaults:
      run:
        shell: sh
    env:
      CONTAINER_NAME: blog_production
    steps:
      - name: Launch Blog Deployment
        run: |
          cd /blog
          docker compose down ${CONTAINER_NAME} 
          docker compose up -d ${CONTAINER_NAME}
          sleep 5
          echo "- Displaying container logs"
          docker compose logs ${CONTAINER_NAME}

  Test-Production:
    needs: Deploy-Production
    runs-on: ubuntu
    env:
      URL: "https://blog.vezpi.com/en/"
    steps:
      - name: Check HTTP Response
        run: |
          code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
          echo "HTTP response code: $code"

          if [ "$code" -ne 200 ]; then
            echo "❌ Service is not healthy (HTTP $code)"
            exit 1
          else
            echo "✅ Service is healthy"
          fi

  Clean:
    needs:
      - Check-Rebuild
      - Build
      - Test-Production
    runs-on: docker
    defaults:
      run:
        shell: sh
    steps:
      - name: Remove Old Docker Image
        run: |
          docker image rm ${{ needs.Check-Rebuild.outputs.current_docker_image }} --force
          
```
## Results

With this new workflow and CI/CD pipeline, I feel much more confident when editing my content in Markdown with Obsidian or tweaking my `hugo` config.

The next step will be to improve the testing phase, a simple `curl` isn’t enough to truly verify that the blog is working properly. I also want to add a notification system to alert me when the workflow fails. See you soon!