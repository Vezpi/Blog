---
slug: notification-system-gotify-vs-ntfy
title: Template
description: 
date: 2025-06-13
draft: true
tags:
  - notification
  - ntfy
  - gotify
categories:
  - homelab
---
## Intro

Pour savoir ce qui se passe dans mon homelab et être averti quand quelque chose ne va pas, je veux mettre en place un système de notifications où (presque) n'importe quoi pourrait m'envoyer un message que je recevrais sur mon mobile.

Par le passé, j’utilisais **Pushover**, qui était très bien, mais je veux explorer de nouvelles options, plus modernes et éventuellement self-hosted.

## Choisir le Bon Système de Notifications

Les éléments clés pour déterminer le bon système pour moi seraient :
- **Application Android** : obligatoire, une interface élégante et intuitive est important.
- **Intégration** : je veux que le service soit intégré partout où je veux être notifié.
- **Self-hosted** : l’héberger moi-même est toujours mieux pour la confidentialité.

Après une recherche rapide, les outils les plus adaptés sur le marché sont :
- **Ntfy**
- **Gotify**

Étant donné les commentaires sur internet et après avoir testé rapidement les deux applications Android, je ne peux pas vraiment décider. Je pense que Ntfy est la meilleure option, mais je vais installer et tester les deux pour me faire une idée !

## Gotify

J’avais entendu parler de Gotify il y a quelque temps, en fait avant même de regarder d'autres alternatives, j'avais celui-ci en tête. J’ai rapidement jeté un œil à sa [documentation](https://gotify.net/docs/) et cela semble assez simple.

### Installation

Comme d’habitude, je vais déployer le serveur Gotify avec `docker compose` sur `dockerVM`, une VM hébergeant mes applications sous forme de conteneurs Docker. Je crée un nouveau dossier `gotify` dans `/appli/docker/` et je colle mon template de `docker-compose.yml` dedans.

`docker-compose.yml`
```yaml
services:
  gotify:
    image: gotify/server
    container_name: gotify
    volumes:
      - /appli/data/gotify/data/:/app/data
    environment:
      - TZ=Europe/Paris
      - GOTIFY_DEFAULTUSER_NAME=${GOTIFY_DEFAULTUSER_NAME}
      - GOTIFY_DEFAULTUSER_PASS=${GOTIFY_DEFAULTUSER_PASS}
    networks:
      - web
    labels:
    - traefik.enable=true
    - traefik.http.routers.gotify.rule=Host(`gotify.vezpi.me`)
    - traefik.http.routers.gotify.entrypoints=https
    - traefik.http.routers.gotify.tls.certresolver=letsencrypt
    - traefik.http.services.gotify.loadbalancer.server.port=80
    restart: always

networks:
  web:
    external: true
```

`.env`
```
GOTIFY_DEFAULTUSER_NAME=vez
GOTIFY_DEFAULTUSER_PASS=<password>
```

Dans la [documentation](https://gotify.net/docs/config), je vois que plusieurs moteurs de base de données peuvent être utilisés, par défaut c’est **sqlite3** qui est utilisé, ce qui ira très bien pour le test. Passer à **PostgreSQL** pourrait être une option si je décide de garder Gotify. Sur cette même page, je vois les différentes variables d’environnement que je peux utiliser pour configurer le serveur depuis le fichier `docker-compose.yml`.

Quand mes fichiers de configuration sont prêts, je crée une nouvelle entrée dans mon plugin Caddy sur OPNsense pour rediriger ma nouvelle URL Gotify : [https://gotify.vezpi.me](https://gotify.vezpi.me).

Je crée également le dossier `/appli/data/gotify/data/` dans `dockerVM` pour le monter comme volume et stocker les données :
```bash
mkdir -p /appli/data/gotify/data/
```

Enfin, je lance la stack docker :
```bash
$ docker compose up -d
[+] Running 5/5
 ✔ gotify Pulled
   ✔ 63ce8e957633 Pull complete
   ✔ e7def9680541 Pull complete
   ✔ 9a1821c438b4 Pull complete
   ✔ ad316556c9ff Pull complete
[+] Running 1/1
 ✔ Container gotify  Started
```

✅ Atteindre l’URL [https://gotify.vezpi.me](https://gotify.vezpi.me) m’affiche la page de connexion Gotify :  
![Gotify login page](img/gotify-login-page.png)

Après connexion, j’accède au tableau de bord, sans messages évidemment :  
![Gotify dashboard on a fresh installation](img/gotify-dashboard-no-messages.png)

### Créer une Application

Pour permettre l’envoi de messages, je dois d’abord créer une application pour laquelle les messages seront regroupés. Cela peut se faire de deux manières :
- **WebUI**
- **REST-API**

Pour le test, j’utiliserai la WebUI, je clique sur le bouton `APPS` en haut puis `CREATE APPLICATION`. Je choisis un magnifique nom d'application et une description.  
![Create an application on Gotify](img/gotify-create-new-application.png)

Une fois mon application créée, un token est généré pour celle-ci. Je peux modifier l’application pour changer quoi que ce soit, je peux aussi uploader une icône.  
![Gotify application list showing my new Potato application](img/gotify-application-list.png)

### Tests

Mon application est maintenant visible dans la barre latérale, testons maintenant l’envoi d’un message. Pour l’envoyer, je peux utiliser `curl` et j’ai besoin du token de l’application.

```bash
curl "https://gotify.vezpi.me/message?token=<apptoken>" -F "title=Cooked!" -F "message=The potoaries are ready!" -F "priority=5"
```
Je reçois instantanément la notification sur mon mobile et dans mon navigateur.

Je renvoie un autre message mais avec une priorité plus basse : `-2`. Je ne reçois pas de notification dans mon navigateur, je remarque une légère différence entre les deux messages. Sur mon mobile, seule ma montre la reçoit, je ne la vois pas sur l’écran, mais je la retrouve dans le centre de notifications.  
![Messages received on Gotify WebUI](img/gotify-messages-received.png)

### Application Android

Voici quelques captures d’écran depuis mon appareil Android :  
![Capture d’écran de l’application Android Gotify pour la page de connexion](img/gotify-android-first-login.png)

Pour une raison inconnue, une notification apparaît aléatoirement pour me dire que je suis connecté à Gotify :  
![Capture d’écran de l’application Android Gotify avec les messages de test](img/gotify-android-test-messages.png)

### Conclusion

Dans la [documentation](https://gotify.net/docs/msgextras), j’ai trouvé quelques fonctionnalités supplémentaires, comme l’ajout d’images ou d’actions cliquables. En résumé, ça fait le job, c’est tout. Le processus d’installation est simple, l’utilisation n’est pas compliquée, mais je dois créer une application pour obtenir un token, puis ajouter ce token à chaque fois que je veux envoyer un message.

## Ntfy

Ntfy semble très propre, installons-le et voyons ce qu’il propose !

### Installation

Même histoire ici avec `docker compose` sur `dockerVM`. Je crée un nouveau dossier `ntfy` dans `/appli/docker/` et je colle le template de `docker-compose.yml`.

`docker-compose.yml`
```yaml
services:
  ntfy:
    image: binwiederhier/ntfy
    container_name: ntfy
    command:
      - serve
    volumes:
      - /appli/data/ntfy/data:/var/cache/ntfy
    environment:
      - TZ=Europe/Paris
      - NTFY_BASE_URL=https://ntfy.vezpi.me
      - NTFY_CACHE_FILE=/var/cache/ntfy/cache.db
      - NTFY_AUTH_FILE=/var/cache/ntfy/auth.db
      - NTFY_ATTACHMENT_CACHE_DIR=/var/cache/ntfy/attachments
      - NTFY_AUTH_DEFAULT_ACCESS=deny-all
      - NTFY_BEHIND_PROXY=true
      - NTFY_ENABLE_LOGIN=true
    user: 1000:1000
    networks:
      - web
    labels:
    - traefik.enable=true
    - traefik.http.routers.ntfy.rule=Host(`ntfy.vezpi.me`)
    - traefik.http.routers.ntfy.entrypoints=https
    - traefik.http.routers.ntfy.tls.certresolver=letsencrypt
    - traefik.http.services.ntfy.loadbalancer.server.port=80
    healthcheck:
      test: ["CMD-SHELL", "wget -q --tries=1 http://ntfy:80/v1/health -O - | grep -Eo '\"healthy\"\\s*:\\s*true' || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped

networks:
  web:
    external: true
```

Je crée aussi le dossier de volume persistant `/appli/data/ntfy/data/` dans `dockerVM` :
```bash
mkdir -p /appli/data/ntfy/data/
```

La [documentation](https://docs.ntfy.sh/config/) est impressionnante, j’ai essayé de rassembler la config pour un démarrage rapide. Je devrais être bon pour lancer le serveur.

Encore une fois ici, je crée un nouveau domaine pour mon proxy inverse Caddy sur OPNsense avec l’URL [https://ntfy.vezpi.me](https://ntfy.vezpi.me).
```bash
$ docker compose up -d
[+] Running 4/4
 ✔ ntfy Pulled
   ✔ f18232174bc9 Already exists
   ✔ f5bf7a328fac Pull complete
   ✔ 572c745ef6c3 Pull complete
[+] Running 1/1
 ✔ Container ntfy  Started
```

✅ L’URL [https://ntfy.vezpi.me](https://ntfy.vezpi.me) me donne accès au tableau de bord Ntfy :  
![Ntfy dashboard](img/ntfy-login-dashboard.png)

Au départ je n’ai aucun utilisateur et aucun n’est créé par défaut. Comme j’ai interdit tout accès anonyme dans la config, je dois en créer un.

Pour lister les utilisateurs, je peux utiliser cette commande :
```bash
$ docker exec -it ntfy ntfy user list
user * (role: anonymous, tier: none)
- no topic-specific permissions
- no access to any (other) topics (server config)
```

Je crée un utilisateur avec les privilèges d’administration :
```bash
$ docker exec -it ntfy ntfy user add --role=admin vez
user vez added with role admin
```

Je peux maintenant me connecter à l’interface Web, et passer en mode sombre, mes yeux me remercient.

### Topics

Dans Ntfy, il n’y a pas d’applications à créer, mais les messages sont regroupés dans des topics, plus lisibles qu’un token lors de l’envoi. Une fois le topic créé, je peux changer le nom d’affichage ou envoyer des messages de test. Sur l’interface Web, cependant, je ne trouve aucune option pour changer l’icône, alors que c’est possible depuis l’application Android, ce qui n’est pas très pratique.
![Example messages in Ntfy](img/ntfy-topic-messages.png)
### Tests

Envoyer un message est en fait plus difficile que prévu. Comme j’ai activé l’authentification, je dois aussi m’authentifier pour envoyer des messages :
```
curl \
  -H "Title: Cooked!" \
  -H "Priority: high" \
  -d "The potatoes are ready!" \
  -u "vez:<password>" \
  https://ntfy.vezpi.me/patato
```

### Application Android

Voici quelques captures de l’application Android Ntfy :  
![Captures de l’application Android Ntfy](img/ntfy-android-app.png)

### Conclusion

Ntfy est une belle application avec une [documentation](https://docs.ntfy.sh/) vraiment solide. Les possibilités sont infinies et la liste des intégrations est impressionnante. L’installation n’était pas difficile mais demandait un peu plus de configuration. Le besoin d’utiliser la CLI pour configurer les utilisateurs et les permissions n’est pas très pratique.

Sur l’application Android, je regrette qu’il n’y ait pas une vue pour voir tous les messages des différents topics. En revanche, sur l’interface Web, j’aurais aimé pouvoir définir les icônes des topics. Ce que j’ai trouvé intéressant, c’est la possibilité d’avoir des topics depuis différents serveurs.

## Comparaison

**Gotify** est simple, tous les utilisateurs auront accès à toutes les applications. Pas besoin d'identifiant utilisateur pour envoyer des messages, seulement le token de l’application. L’application Android est efficace, mais personnellement, même si l’icône est amusante, je ne l’aime pas trop.

**Ntfy** semble plus avancé et complet, avec des permissions plus précises. L’interface est élégante tout en restant simple, les possibilités sont infinies.

Dans l’ensemble, seuls de petits détails me font préférer Ntfy à Gotify, par exemple, avoir accès à des topics de différents serveurs, les ACL ou la possibilité d’ajouter des émojis aux messages, mais les deux applications remplissent bien leur rôle.

## Implémentation de Notifications Réelles

Pendant que je mettais en place mon pipeline CI/CD pour le déploiement de mon blog, je voulais être averti chaque fois que quelque chose se passe, voyons comment je peux l’implémenter avec Ntfy.

### Contrôle d’Accès

Je pourrais utiliser mon utilisateur `admin` pour envoyer les messages depuis le pipeline et les recevoir sur mon appareil Android, même si c’est plus simple à configurer, je veux appliquer le principe de moindre privilège, ce que Ntfy permet. Je vais donc créer un utilisateur dédié pour mon pipeline CI/CD et un autre pour mon appareil Android.

#### Utilisateur Pipeline

Celui-ci ne pourra qu'envoyer des messages sur le topic `blog`, je l’appelle `gitea_blog`.
```bash
$ ntfy user add gitea_blog
user gitea_blog added with role user
$ ntfy access gitea_blog blog wo
granted write-only access to topic blog

user gitea_blog (role: user, tier: none)
- write-only access to topic blog
```

Je teste rapidement l’envoi d’un message sur ce topic :
```bash
$ curl -u gitea_blog:<password> -d "Message test from gitea_blog!" https://ntfy.vezpi.me/blog
{"id":"xIgwz9dr1w9Z","time":1749587681,"expires":1749630881,"event":"message","topic":"blog","message":"Message test from gitea_blog!"}
```

![Test d’envoi de messages sur le topic blog avec Ntfy  ](img/ntfy-testing-gitea-blog-user.png)
✅ Message reçu !

Je tente aussi un envoi sur mon topic de test :
```bash
$ curl -u gitea_blog:<password> -d "Message test from gitea_blog!" https://ntfy.vezpi.me/potato
{"code":40301,"http":403,"error":"forbidden","link":"https://ntfy.sh/docs/publish/#authentication"}
```
❌ Denied as expected.

#### Android Device User

From my Android device I only want to receive messages, but on all topics. I create the user `android_s25u`:
```bash
$ ntfy user add android_s25u
user android_s25u added with role user
$ ntfy access android_s25u "*" ro
granted read-only access to topic *

user android_s25u (role: user, tier: none)
- read-only access to topic *
```

✅ After setting up the user on the Ntfy Android App, I can read my messages on the `blog` and on the testing one.

### Implementation

Now my users are setup, I want to add a `Notify` job in my CI/CD pipeline for the blog deployment in **Gitea**, you can find the full workflow in [this article]({{< ref "post/4-blog-deployment-ci-cd-pipeline-gitea-actions" >}}).

#### Create a Secret

To allow my Gitea Runner to use my `gitea_blog` user in its job, I want to create a secret. I explore the `Blog` Gitea repository `Settings`, then `Actions` > `Secrets` > `Add Secret`. Here I set the secret value with the `<user>:<password>` format:
![Add a secret in the blog Gitea repository](img/gitea-blog-ntfy-credentials.png)

### Write the `Notify` code

Now I can write the code which will send me a message when a new deployment occurs.

If the deployment is successful, the priority would be minimal, no notifications needed on my mobile, just for me to view the events in the Android Ntfy App if I need to.

If anything fails, I want to be notified on my mobile with higher priority. Ntfy allows me to add actions on my notifications, I will create 2 actions:
- **View Run**: Direct link to the workflow run in Gitea to see what happened.
- **Verify Blog**: Link to the blog to make sure it is still online.
```yaml
  Notify:
    needs: [Check-Rebuild, Build, Deploy-Staging, Test-Staging, Merge, Deploy-Production, Test-Production, Clean]
    runs-on: ubuntu
    if: always()
    env:
      NTFY_URL: https://ntfy.vezpi.me
      NTFY_TOPIC: blog
      NTFY_TOKEN: ${{ secrets.NTFY_CREDENTIALS }}
    steps:
      - name: Notify Workflow Result
        run: |
          if [[
            "${{ needs.Check-Rebuild.result }}" == "success" &&
           ("${{ needs.Build.result }}" == "success" || "${{ needs.Build.result }}" == "skipped") &&
            "${{ needs.Deploy-Staging.result }}" == "success" &&
            "${{ needs.Test-Staging.result }}" == "success" && 
            "${{ needs.Merge.result }}" == "success" &&
            "${{ needs.Deploy-Production.result }}" == "success" &&
            "${{ needs.Test-Production.result }}" == "success" &&
           ("${{ needs.Clean.result }}" == "success" || "${{ needs.Clean.result }}" == "skipped")
          ]]; then
            curl -H "Priority: min" \
                 -H "Tags: white_check_mark" \
                 -d "Blog workflow completed successfully." \
                 -u ${NTFY_TOKEN} \
                 ${NTFY_URL}/${NTFY_TOPIC}
          else
            curl -H "Priority: high" \
                 -H "Tags: x" \
                 -H "Actions: view, View Run, ${{ gitea.server_url }}/${{ gitea.repository }}/actions/runs/${{ gitea.run_number }}, clear=true; \
                              view, Verify Blog, https://blog.vezpi.com, clear=true" \
                 -d "Blog workflow failed!" \
                 -u ${NTFY_TOKEN} \
                 ${NTFY_URL}/${NTFY_TOPIC}
          fi
```

✅ Testing both cases work as expected
![Checking both test scenario in Ntfy WebUI](img/ntfy-testing-blog-notifications.png)

## Conclusion

After testing **Gotify** and **Ntfy**, I found my next notification system. They are both good for the job but I had to pick one and I have a little preference for Ntfy.

The application would be perfect if I could manage the users and access from the WebUI, also I would prefer to manage the topic's icon globally and not having to upload it from my mobile.

Anyway I'm very satisfied with the results on my first implementation and I look forward to add notification elsewhere!