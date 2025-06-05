---
slug: blog-deployment-ci-cd-pipeline-gitea-actions
title: Pipeline CI/CD du Déploiment du Blog avec Gitea Actions
description: Comment j'ai sécurisé le déploiement automatisé de mon blog self-hosted construit avec Hugo en mettant en place un pipeline CI/CD à l'aide de Gitea Actions
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

Maintenant que mon blog est en ligne, je ne peux plus vraiment me permettre de le faire tomber à la moindre modification. J'avais bien une version "preview" de mon blog qui était générée en même temps que la version publique, mais celle-ci reposait sur le même contenu et me permettait uniquement de voir les pages en mode brouillon.

Le blog étant redéployé de façon automatique à chaque modification du contenu dans Obsidian, détaillé dans [cet article]({{< ref "post/2-blog-deployment-obisidan-hugo-gitea-actions" >}}), je ne vérifie pas systématiquement si le déploiement s'est planté ou non. Je devais donc trouver une solution pour le protéger de mes bêtises. 

## Sécuriser le Déploiement du Blog

Aujourd'hui mon blog se redéploie automatiquement à chaque modification de la branche `main` du [dépôt Git](https://git.vezpi.me/Vezpi/Blog) de mon instance **Gitea** via une **Gitea Actions**. Chaque modification apportée à mon vault **Obsidian** est poussée automatiquement dans cette branche.

![Workflow depuis l'écriture de notes sur Obsidian au Blog publié](img/obsidian-blog-gitea-actions-workflow.png)

### Créer une Nouvelle Branche

La première partie, la plus simple, a donc été de créer une nouvelle branche qui allait recevoir ces modifications. J'ai donc crée la branche `preview` dans ce dépôt. Ensuite j'ai modifié la branche cible recevant les modifications dans le workflow de mon dépôt Git Obsidian.

![Create the preview branch from the main branch in Gitea](img/gitea-create-new-branch.png)

### Containeriser le Blog

Le blog généré avec **Hugo** est sous forme de fichiers statiques, qui sont localisés sur un filesystem de ma Machine Virtuelle `dockerVM`, et montés sous forme de volume dans un conteneur `nginx`.

Je ne voulais plus avoir ces fichiers montés dans un volume, mais qu'ils soient générés au lancement du conteneur, ainsi je pourrai faire vivre plusieurs instances indépendantes de mon blog.

Pour la 2ème partie, il me faut donc construire une image **Docker** qui doit réaliser ces opérations:
1. Télécharger le binaire `hugo`.
2. Cloner le dépôt Git de mon blog.
3. Générer les pages statiques avec `hugo`.
4. Servir les pages web.

#### Construire l'Image Docker

Un conteneur Docker est basé sur une image, un modèle contenant déjà des instructions exécutées à l'avance. Une fois le conteneur démarré, il peut alors exécuter une autre série d’actions, comme lancer un serveur ou un script.

Pour construire une image Docker, il faut un fichier appelé `Dockerfile` qui regroupe les actions a effectuer pour sa construction, on peut également y ajouter d'autres fichiers, comme ici un script nommé `entrypoint.sh` qui sera alors le processus lancé au démarrage du conteneur.
```plaintext
docker/
├── Dockerfile
├── entrypoint.sh
└── nginx.conf
```

##### Dockerfile

Dans mon cas je voulais que l'image, basé sur `nginx`, contienne la configuration du serveur web, le binaire `hugo`, qu'elle soit capable de cloner mon dépôt Git et qu'elle lance un script à son exécution.
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

Par défaut, au lancement d'un conteneur `nginx`, il se contente de lancer le serveur web. Ici je voulais qu'avant cela, qu'il clone une branche du dépôt Git de mon blog et qu'à partir de cette branche, il génère les fichiers statiques avec `hugo`.
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

Je spécifie ici à `hugo` de sortir en erreur dès qu'un warning est généré, cela empêchera le conteneur de démarré correctement et pouvoir identifier un éventuel problème.

Je peux maintenant construire mon image Docker, avec comme argument, la version d'Hugo désiré :
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

✅ Maintenant que j'ai mon image, je peux lancer une nouvelle instance de mon blog, sans me préoccuper de ce que j'ai actuellement sur le FS de ma VM. Je peux également choisir à partir de quelle branche de mon dépôt Git, le contenu sera généré.

Mais je ne peux toujours pas prédire si ces instances sont fonctionnelles, il me faut pouvoir les **tester** et enfin les **déployer**.

Afin d'automatiser ce déploiement, je vais construire un **Pipeline CI/CD**.

### Pipeline CI/CD

Un pipeline CI/CD est une suite d'étapes automatisées qui permettent de tester, construire et déployer une application. La partie **CI (Intégration Continue)** vérifie que le code fonctionne bien à chaque modification (par exemple en lançant des tests), tandis que la **CD (Déploiement Continu)** s’occupe de livrer automatiquement ce code vers un environnement de test ou de production. Cela rend les mises à jour plus rapides, fiables et régulières.

Il existe plusieurs outils :
- **CI** : Jenkins, Travis CI, etc.
- **CD** Argo CD, Flux CD, etc.
- **CI/CD** : GitLab CI/CD, GitHub Actions, etc.

Dans mon cas je vais réutiliser les **Gitea Actions** très similaire à GitHub Actions, une plateforme CI/CD intégré à **Gitea**, qui fonctionne avec des workflows définis dans des fichiers `YAML` placés dans le dépôt Git.

À chaque événement, comme un push ou une création de tag, Gitea Actions va lancer automatiquement une série d’étapes (tests, build, déploiement…) dans un environnement isolé, basé sur des conteneurs Docker.

#### Gitea Runners

Les workflows Gitea Actions utilisent des **Gitea Runners**, ils récupèrent les jobs et les lancent dans des conteneurs Docker, assurant un environnement propre et isolé pour chaque étape.

Comme les instances de mon blog sont gérées par `docker` (précisément par `docker compose`), je voulais que le `runner` puisse interagir avec le démon Docker de `dockerVM`. Pour ce faire, j'ai du ajouter au catalogue de mon `runner` l'image `docker:cli` et lui donner accès au `docker.socket` de la VM.

Voici la nouvelle configuration de mon `runner` dans ma stack Gitea, gérée par `docker compose` également :
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

Avant j'utilisais un workflow simple qui était déclenché à chaque push sur la branche `main` du dépôt Git de mon blog, voici ce qu'il faisait :
1. Checkout de mon dépôt Git dans le FS de ma VM `dockerVM`.
2. Télécharge le binaire `hugo` si une nouvelle version était disponible.
3. Génère les fichiers statiques du blog avec `hugo`.

Maintenant voici ce que le nouveau workflow fait :
1. **Check-Rebuild** : Vérifie si une nouvelle version d'Hugo est disponible et vérifie si le dossier `docker` du dépôt a été modifié.
2. **Build** : Si le job précédent le suggère, reconstruit l'image Docker `vezpi-blog` et la tag avec la version d'Hugo.
3. **Deploy-Staging** : Déploie le blog avec la branche `preview` sur une URL de test avec `docker compose`.
4. **Test-Staging** : Vérifie que le blog en version `preview` répond et fonctionne.
5. **Merge** : Merge la branche `preview` avec la branche `main`.
6. **Deploy-Production** : Déploie le blog avec la branche  `main`, la version publique avec `docker compose`.
7. **Test-Production** : Vérifie que le blog en version `main` répond et fonctionne.
8. **Clean** : Supprime l'ancienne image Docker.

Voici un exemple de déploiement après un commit automatique généré par **Obsidian**, on peut voir ici que l'image Docker n'a pas été reconstruire car il n'y avait pas de nouvelle version d'Hugo disponible et que le dossier `docker` n'avait pas été modifié, de ce fait, le dernier job `Clean` n'était pas non plus nécessaire.

![Gitea Actions workflow for blog deployment](img/gitea-actions-deploy-blog-workflow.png)

#### Code

Le workflow est écrit en `YAML` et doit être localisé dans le répertoire `.gitea/workflows/` du dépôt Git.
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
## Résultats

Avec ce nouveau workflow et ce pipeline CI/CD, je suis beaucoup plus serein lorsque je modifie le contenu de mes pages depuis Obsidian en Markdown ou lorsque je modifie la configuration d'`hugo`.

La prochaine étape sera de renforcer l'étape des tests, un simple `curl` n'est clairement pas suffisant pour s'assurer le bon fonctionnement du blog. Je veux aussi rajouter un système de notification pour m'alerter lorsque le workflow se plante. A bientôt !