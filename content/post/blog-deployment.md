---
title: Blog Deployment featuring Obsidian, Hugo and Gitea Actions
date: 2025-05-02
draft: false
tags:
  - obsidian
  - hugo
  - gitea
categories:
  - homelab
---
## 💡 Intro

I always wanted to share my own experiences to give others ideas or help them on their projects.

I'm constantly tinkering in my homelab, trying new tools and workflows. Instead of keeping all these experiments in private notes, I decided to create a blog where I can document and publish them easily.

I wanted the entire process to be automated, self-hosted, and integrated into the tools I already use.

---
## 🔧 Tools
### Obsidian

Before I was using  [Notion](https://www.notion.com), but some months ago I switched to [Obsidian](https://obsidian.md/). It's a markdown-based note-taking app that stores everything locally, which gives me more flexibility and control.

To sync my notes between devices, I use the [Obsidian Git plugin](https://github.com/denolehov/obsidian-git), which commits changes to a Git repository hosted on my self-hosted Gitea instance.

This setup not only allows for versioned backups of all my notes but also opens the door to automation.

### Gitea

[Gitea](https://gitea.io/) est un service Git self-hosted similaire à GitHub, mais léger et facile à maintenir. J'y héberge mes dépôts personnels, notamment mon vault Obsidian et mon blog.

Gitea prend désormais en charge [Gitea Actions](https://docs.gitea.com/usage/actions/overview), un mécanisme de pipeline CI/CD compatible avec la syntaxe GitHub Actions.

Pour exécuter ces workflows, j'ai installé un [Gitea runner](https://gitea.com/gitea/act_runner) sur mon serveur, ce qui me permet de créer un workflow automatisé déclenché lorsque je mets à jour le contenu de mes notes, puis de reconstruire et déployer mon blog.

### Hugo

[Hugo](https://gohugo.io/) est un générateur de sites statiques rapide et flexible, écrit en Go. Il est idéal pour générer du contenu à partir de fichiers Markdown. Hugo est hautement personnalisable, prend en charge les thèmes et peut générer un site web complet en quelques secondes. Il est idéal pour un blog basé sur des notes Obsidian et fonctionne parfaitement dans les pipelines CI/CD grâce à sa rapidité et sa simplicité.

---
## 🔁 Workflow

L'idée est simple :
1. J'écris le contenu de mon blog dans mon vault Obsidian, sous un dossier `Blog`.
2. Une fois le fichier modifié, le plugin Git Obsidian effectue automatiquement les commits et les poussent vers le dépôt Gitea.
3. Lorsque Gitea reçoit ce push, une première action Gitea est déclenchée.
4. La première action synchronise le contenu du blog mis à jour avec un autre dépôt [Git distinct](https://git.vezpi.me/Vezpi/blog) qui héberge le contenu.
5. Dans ce dépôt, une autre action Gitea est déclenchée.
6. La deuxième action Gitea génère les pages web statiques tout en mettant à jour Hugo si nécessaire.
7. Le blog est maintenant mis à jour (celui que vous lisez).

De cette façon, je n'ai plus besoin de copier manuellement de fichiers ni de déclencher de déploiements. Tout se déroule comme prévu, de l'écriture de Markdown dans Obsidian au déploiement complet du site web.

---
## ⚙️ Implémentation

### Étape 1 : Configuration du vault Obsidian

Dans mon vault Obsidian, j'ai créé un dossier `Blog` contenant mes articles de blog en Markdown. Chaque article inclut les pages de garde Hugo (titre, date, brouillon, etc.). Le plugin Git est configuré pour valider et pousser automatiquement les modifications apportées au dépôt Gitea.

### Étape 2 : Lancer Gitea Runner

Le vault Obsidian est un dépôt Git privé self-hosted dans Gitea. J'utilise Docker Compose pour gérer cette instance. Pour activer les actions Gitea, j'ai ajouté Gitea Runner à la stack.
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

Le fichier `config.yml` contient uniquement le volume autorisé à monter dans les conteneurs
```yaml
container:
  valid_volumes:
    - /appli*
```

Le runner apparaît dans `Administration Area`, sous `Actions`>`Runners`. Pour obtenir le token d'enrôlement , on clique sur le bouton `Create new Runner` 
![Pasted_image_20250502230954.png](img/Pasted_image_20250502230954.png)

### Step 3: Set up Gitea Actions for Obsidian Repository

First I enabled the Gitea Actions, this is disabled by default, tick the box `Enable Repository Actions`  in the settings for that repository

I created a new PAT (Personal Access Token) with RW permission on the repositories
![Pasted_image_20250501235521.png](img/Pasted_image_20250501235521.png)

I added this token as secret `REPO_TOKEN` in the repository
![Pasted_image_20250501235427.png](img/Pasted_image_20250501235427.png)

I needed to create the workflow that will spin-up a container and do the following:
- When I push new/updated files in the `Blog` folder
- Checkout the current repository (Obsidian vault)
- Clone the blog repository
- Transfer blog content from Obsidian
- Commit the change to the blog repository

**sync_blog.yml**
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
        run: |
          echo "Copy Markdown files"
          rsync -av --delete Blog/ blog/content
          # Gather all used images from markdown files
          used_images=$(grep -rhoE '^!\[\[.*\]\]' blog/content | sed -E 's/!\[\[(.*)\]\]/\1/' | sort -u)
          # Create the target image folder
          mkdir -p blog/static/img
          # Loop over each used image"
          while IFS= read -r image; do
            # Loop through all .md files and replace image links
            grep -rl "$image" blog/content/* | while IFS= read -r md_file; do
              sed -i "s|\!\[\[$image\]\]|\!\[${image// /_}\](img/${image// /_})|g" "$md_file"
            done
            echo "Copy the image ${image// /_} to the static folder"
            cp "Images/$image" "blog/static/img/${image// /_}"
          done <<< "$used_images"

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

Obsidian uses wiki-style links for images, like `![image_name.png](img/image_name.png)`, which isn't compatible with Hugo out of the box. Here's how I automated a workaround in a Gitea Actions workflow:
- I find all used image references in `.md` files.
- For each referenced image, I update the link in relevant `.md` files like `![image name](img/image_name.png)`.
- I then copy those used images to the blog's static directory while replacing white-spaces by underscores.

### Step 4: Gitea Actions for Blog Repository

The blog repository contains the full Hugo site, including the synced content and theme.

Its workflow:
- Checkout the blog repository
- Check if the Hugo version is up-to-date. If not, it downloads the latest release and replaces the old binary.
- Build the static website using Hugo.

**deploy_blog.yml**
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
      - name: Check out repository
        run: |
          cd ${BLOG_FOLDER}
          git config --global user.name "Gitea Actions"
          git config --global user.email "actions@local"
          git config --global --add safe.directory ${BLOG_FOLDER}
          git submodule update --init --recursive
          git fetch origin
          git reset --hard origin/main

      - name: Get current Hugo version
        run: |
          current_version=$(${BLOG_FOLDER}/hugo version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
          echo "current_version=$current_version" | tee -a $GITEA_ENV

      - name: Verify latest Hugo version
        run: |
          latest_version=$(curl -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep -oP '"tag_name": "\K[^"]+')
          echo "latest_version=$latest_version" | tee -a $GITEA_ENV

      - name: Download latest Hugo version
        if: env.current_version != env.latest_version
        run: |
          rm -f ${BLOG_FOLDER}/{LICENSE,README.md,hugo}
          curl -L https://github.com/gohugoio/hugo/releases/download/$latest_version/hugo_extended_${latest_version#v}_Linux-64bit.tar.gz -o hugo.tar.gz
          tar -xzvf hugo.tar.gz -C ${BLOG_FOLDER}/

      - name: Generate the static files with Hugo
        run: |
          rm -f ${BLOG_FOLDER}/content/posts/template.md
          rm -rf ${BLOG_FOLDER}/private/* ${BLOG_FOLDER}/public/*
          ${BLOG_FOLDER}/hugo -D -b https://blog-dev.vezpi.me -s ${BLOG_FOLDER} -d ${BLOG_FOLDER}/private
          ${BLOG_FOLDER}/hugo -s ${BLOG_FOLDER} -d ${BLOG_FOLDER}/public
          chown 1000:1000 -R ${BLOG_FOLDER}
```

---
## 🚀 Results

This workflow allows me to focus on what matters most: writing and refining my content. By automating the publishing pipeline — from syncing my Obsidian notes to building the blog with Hugo — I no longer need to worry about manually managing content in a CMS.

Every note I draft can evolve naturally into a clear, structured article, and the technical workflow fades into the background. It’s a simple yet powerful way to turn personal knowledge into shareable documentation.