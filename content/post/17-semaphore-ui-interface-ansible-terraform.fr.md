---
slug: semaphore-ui-interface-ansible-terraform
title: Semaphore UI, une excellente interface pour Ansible et Terraform
description: Démonstration de Semaphore UI, une interface web pour exécuter des playbooks Ansible, du code Terraform et bien plus. Installation avec Docker et exemples rapides.
date: 2026-02-09
draft: true
tags:
  - semaphore-ui
  - ansible
  - terraform
  - proxmox
  - docker
categories:
  - homelab
---
## Intro

Dans mon homelab, j'aime expérimenter avec des outils comme Ansible et Terraform. L'interface principale est le CLI, que j'adore, mais parfois une jolie interface web est juste agréable.

Après avoir configuré mon cluster OPNsense, je voulais un moyen de le tenir à jour selon un calendrier. Pour moi, l'automatisation passe par Ansible, mais comment automatiser et planifier des playbooks ?

Au travail j'utilise Red Hat Ansible Automation Platform, qui est excellent, mais overkill pour mon lab. C'est ainsi que j'ai découvert Semaphore UI. Voyons ce qu'il peut faire.

---
## Qu'est‑ce que Semaphore UI

[Semaphore UI](https://semaphoreui.com/docs/) est une interface web élégante conçue pour exécuter de l'automatisation avec des outils comme Ansible et Terraform, et même des scripts Bash, Powershell ou Python.

Initialement créé sous le nom Ansible Semaphore, une interface web destinée à fournir un front-end simple pour exécuter uniquement des playbooks Ansible. Au fil du temps, la communauté a fait évoluer le projet en une plateforme de contrôle d'automatisation multi‑outils.

C'est une application autonome écrite en Go avec des dépendances minimales, capable d'utiliser différents backends de base de données, tels que PostgreSQL, MySQL ou BoltDB.

---
## Installation

Semaphore UI prend en charge plusieurs méthodes d'[installation](https://semaphoreui.com/docs/category/installation) : Docker, Kubernetes, gestionnaire de paquets ou simple binaire.

J'ai utilisé Docker pour mon installation, vous pouvez voir comment je déploie actuellement des applications dans ce [post]({{< ref "post/16-how-I-deploy-application" >}})

Voici mon fichier `docker-compose.yml` que j'ai configuré en utilisant PostgreSQL :
```yaml
services:
  semaphore:
    image: semaphoreui/semaphore:v2.16.45
    container_name: semaphore_ui
    environment:
      - TZ=Europe/Paris
      - SEMAPHORE_DB_USER=${POSTGRES_USER}
      - SEMAPHORE_DB_PASS=${POSTGRES_PASSWORD}
      - SEMAPHORE_DB_HOST=postgres 
      - SEMAPHORE_DB_PORT=5432 
      - SEMAPHORE_DB_DIALECT=postgres
      - SEMAPHORE_DB=${POSTGRES_DB}
      - SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
      - SEMAPHORE_ADMIN_PASSWORD=${SEMAPHORE_ADMIN_PASSWORD}
      - SEMAPHORE_ADMIN_NAME=${SEMAPHORE_ADMIN_NAME}
      - SEMAPHORE_ADMIN_EMAIL=${SEMAPHORE_ADMIN_EMAIL}
      - SEMAPHORE_ADMIN=${SEMAPHORE_ADMIN}
      - SEMAPHORE_ACCESS_KEY_ENCRYPTION=${SEMAPHORE_ACCESS_KEY_ENCRYPTION}
      - SEMAPHORE_LDAP_ACTIVATED='no'
      # - SEMAPHORE_LDAP_HOST=dc01.local.example.com
      # - SEMAPHORE_LDAP_PORT='636'
      # - SEMAPHORE_LDAP_NEEDTLS='yes'
      # - SEMAPHORE_LDAP_DN_BIND='uid=bind_user,cn=users,cn=accounts,dc=local,dc=shiftsystems,dc=net'
      # - SEMAPHORE_LDAP_PASSWORD='ldap_bind_account_password'
      # - SEMAPHORE_LDAP_DN_SEARCH='dc=local,dc=example,dc=com'
      # - SEMAPHORE_LDAP_SEARCH_FILTER="(\u0026(uid=%s)(memberOf=cn=ipausers,cn=groups,cn=accounts,dc=local,dc=example,dc=com))"
    depends_on:
      - postgres
    networks:
      - backend
      - web
    labels:
      - traefik.enable=true
      - traefik.http.routers.semaphore.rule=Host(`semaphore.vezpi.com`)
      - traefik.http.routers.semaphore.entrypoints=https
      - traefik.http.routers.semaphore.tls.certresolver=letsencrypt
      - traefik.http.services.semaphore.loadbalancer.server.port=3000
    restart: unless-stopped

  postgres:
    image: postgres:14
    hostname: postgres
    container_name: semaphore_postgres
    volumes:
     - /appli/data/semaphore/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    networks:
      - backend
    restart: unless-stopped

networks:
  backend:
  web:
    external: true
```

Pour générer les clés d'accès chiffrées, j'utilise cette commande :
```bash
head -c32 /dev/urandom | base64
```

Avec Semaphore en fonctionnement, faisons rapidement le tour de l'UI et connectons-la à un dépôt.

---
## Discovery

Après avoir démarré la stack, je peux atteindre la page de connexion à l'URL :
![Page de connexion de Semaphore UI](img/semaphore-login-page.png)

Pour me connecter, j'utilise les identifiants définis par `SEMAPHORE_ADMIN_NAME`/`SEMAPHORE_ADMIN_PASSWORD`.

Au premier accès, Semaphore me demande de créer un projet. J'ai créé le projet Homelab :
![Page de création de projet de Semaphore UI](img/semaphore-create-project.png)

La première chose que je veux faire est d'ajouter mon dépôt _homelab_ (vous pouvez trouver son miroir sur Github [ici](https://github.com/Vezpi/homelab)). Dans `Repository`, je clique sur le bouton `New Repository`, et j'ajoute l'URL du repo. Je ne spécifie pas d'identifiants car le dépôt est public :
![Page d'ajout de dépôt de Semaphore UI](img/semaphore-add-repository.png)

ℹ️ Avant de continuer, je déploie 3 VM à des fins de test : `sem01`, `sem02` et `sem03`. Je les ai créées avec Terraform via [ce projet](https://github.com/Vezpi/Homelab/tree/main/terraform/projects/semaphore-vms).

Pour interagir avec ces VM, je dois configurer des identifiants. Dans le `Key Store`, j'ajoute la première donnée d'identification, une clé SSH pour mon utilisateur :
![Page d'ajout d'une nouvelle clé de Semaphore UI](img/semaphore-create-new-ssh-key.png)

Ensuite je crée un nouvel `Inventory`. J'utilise le format d'inventaire Ansible (le seul disponible). Je sélectionne la clé SSH créée précédemment et choisis le type `Static`. Dans les champs je renseigne les 3 hôtes créés avec leur FQDN :
![Page de création d'un inventaire statique de Semaphore UI](img/semaphore-create-new-static-inventory.png)

✅ Avec un projet, un repo, des identifiants et un inventaire en place, je peux avancer et tester l'exécution d'un playbook Ansible.

---
## Launching an Ansible playbook

Je veux tester quelque chose de simple : installer un serveur web avec une page personnalisée sur ces 3 VM. Je crée le playbook `install_nginx.yml` :
```yaml
---
- name: Demo Playbook - Install Nginx and Serve Hostname Page
  hosts: all
  become: true

  tasks:
    - name: Ensure apt cache is updated
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present

    - name: Create index.html with hostname
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        content: |
          <html>
          <head><title>Demo</title></head>
          <body>
              <h1>Hostname: {{ inventory_hostname }}</h1>
          </body>
          </html>
        owner: www-data
        group: www-data
        mode: "0644"

    - name: Ensure nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
```

Dans Semaphore UI, je peux maintenant créer mon premier `Task Template` pour un playbook Ansible. Je lui donne un nom, le chemin du playbook (depuis le dossier racine du repo), le dépôt et sa branche :
![Nouveau template de tâche Ansible dans Semaphore UI](img/semaphore-create-new-ansible-task-template.png)

Il est temps de lancer le playbook ! Dans la liste des task templates, je clique sur le bouton ▶️ :
![Lancement du template de tâche Ansible dans Semaphore UI](img/semaphore-run-test-playbook.png)

Le playbook se lance et je peux suivre la sortie en temps réel :
![Semaphore UI Ansible task output](img/semaphore-ui-ansible-task-output.png)

Je peux aussi consulter les exécutions précédentes :
![Liste des exécutions de tâches dans Semaphore UI](img/semaphore-ui-task-template-run-list.png)


✅ Enfin, je peux confirmer que le travail est fini en vérifiant l'URL sur le port 80 (http) :
![Test de l'URL après application du playbook sur les hôtes](img/semaphore-ui-test-nginx-page-playbook.png)

Gérer des playbooks Ansible dans Semaphore UI est assez simple et vraiment pratique. L'interface est très soignée.

Il existe aussi beaucoup d'options de personnalisation lors de la configuration d'un task template. Je peux utiliser des variables via un survey, spécifier un limit ou des tags. J'apprécie vraiment cela.

---
## Déploiement avec Terraform

Alors que l'exécution des playbooks Ansible était simple dès le départ, le déploiement avec Terraform sur Proxmox VE a été un peu différent. Avant de commencer, je détruis les 3 VM déployées précédemment.

Auparavant depuis le CLI, j'interagissais avec Terraform sur le cluster Proxmox en utilisant une clé SSH. Je n'ai pas réussi à le faire fonctionner depuis Semaphore UI. J'ai dû utiliser un nom d'utilisateur avec un mot de passe à la place.

Je me suis dit que c'était une bonne occasion d'utiliser Ansible pour créer un utilisateur Proxmox dédié. Ma première exécution a échoué avec :
```plaintext
Unable to encrypt nor hash, passlib must be installed. No module named 'passlib'
```

C'est apparemment un problème connu de l'environnement Python de Semaphore. Comme contournement, j'ai installé `passlib` directement dans le conteneur :
```bash
docker exec -it semaphore_ui pip install passlib
```

Avec cela en place, le playbook a réussi et j'ai pu créer l'utilisateur :
```yaml
---
- name: Create Terraform local user for Proxmox
  hosts: nodes
  become: true
  tasks:
  
    - name: Create terraform user
      ansible.builtin.user:
        name: "{{ terraform_user }}"
        password: "{{ terraform_password | password_hash('sha512') }}"
        shell: /bin/bash

    - name: Create sudoers file for terraform user
      ansible.builtin.copy:
        dest: /etc/sudoers.d/{{ terraform_user }}
        mode: '0440'
        content: |
          {{ terraform_user }} ALL=(root) NOPASSWD: /sbin/pvesm
          {{ terraform_user }} ALL=(root) NOPASSWD: /sbin/qm
          {{ terraform_user }} ALL=(root) NOPASSWD: /usr/bin/tee /var/lib/vz/*
```

Ensuite je crée un variable group `pve_vm`. Un variable group me permet de définir plusieurs variables et secrets ensemble :
![Nouveau groupe de variables dans Semaphore UI](img/semaphore-ui-create-variable-group.png)

Puis je crée un nouveau task template, cette fois de type Terraform Code. Je lui donne un nom, le chemin du projet Terraform, un workspace, le dépôt avec sa branche et le variable group :
![Nouveau template de tâche Terraform dans Semaphore UI](img/semaphore-task-template-terraform.png)

Lancer le template me donne quelques options supplémentaires liées à Terraform :
![Options d'exécution Terraform dans Semaphore UI](img/semaphore-running-terraform-code-options.png)

Après le plan Terraform, il me propose d'appliquer, d'annuler ou d'arrêter :
![Plan Terraform dans Semaphore UI](img/semaphore-terraform-task-working.png)

Enfin, après avoir cliqué sur ✅ pour appliquer, j'ai pu regarder Terraform construire les VM, comme avec le CLI. À la fin, les VM ont été déployées avec succès sur Proxmox :
![Déploiement Terraform terminé dans Semaphore UI](img/semaphore-ui-deploy-with-terraform.png)

---
## Conclusion

Voilà pour mes tests de Semaphore UI, j'espère que cela vous aidera à voir ce que vous pouvez en faire.

Dans l'ensemble, l'interface est propre et agréable à utiliser. Je peux tout à fait m'imaginer planifier des playbooks Ansible avec elle, comme les mises à jour OPNsense dont je parlais en intro.

Pour Terraform, je l'utiliserai probablement pour lancer des VM éphémères pour des tests. J'aimerais utiliser le backend HTTP pour tfstate, mais cela nécessite la version Pro.

Pour conclure, Semaphore UI est un excellent outil, intuitif, esthétique et pratique. Beau travail de la part du projet !