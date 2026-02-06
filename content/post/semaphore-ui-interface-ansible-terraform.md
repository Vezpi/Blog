---
slug: 
title: Template
description: 
date: 
draft: true
tags: 
categories:
---
## Intro

In my homelab, I like to play around with tools like Ansible and Terraform. But the principal way to interact with those tools is the CLI. I love the CLI, but sometime a fancy web interface is great.

After having setup my OPNsense cluster, I wanted a way to keep it up to date. Of course I wanted it to be automated, so I thought about creating an Ansible playbook. But how to automate and schedule an Ansible playbook?

In my work environment, I'm using the Red Hat Ansible Automation Platform, which is great, but not suitable in my lab environment. That's how I found Semaphore UI. Let's see what this can do!

---
## What is Semaphore UI

[Semaphore UI](https://semaphoreui.com/docs/) is a sleek web interface designed to manage and run tasks using tools like Ansible and Terraform, but also Bash, Powershell or even Python scripts.

Initially began as Ansible Semaphore, a web interface created to provide a simple front-end for running solely Ansible playbooks. Over time the community evolved the project into a multi-tool automation control plane.

It is a self-contained Go application with minimal dependencies capable of using different database backend, such as PostgreSQL, MySQL, or BoltDB. 

---
## Installation

Semaphore UI supports many ways to [install](https://semaphoreui.com/docs/category/installation) it: Docker, Kubernetes, package manager or simple binary file.

I'll use Docker for my installation, you can see how I deploy application currently in this [post]({{< ref "post/16-how-I-deploy-application" >}})

Here my `docker-compose.yml` file I've configured using PostgreSQL:
```yml
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

To generate the encrypting access keys, I use this command:
```bash
head -c32 /dev/urandom | base64
```

<<<<<<< HEAD
Now I'm able to reach to the login page using the URL configured.

=======
---
>>>>>>> 84ba140 (Update: 2026-02-05 20:52:50)
## Discovery

After starting the stack, I'm able to reach the login page using the URL.
![Semaphore UI login page](img/semaphore-login-page.png)

To login, I use the credentials defined by `SEMAPHORE_ADMIN_NAME`/`SEMAPHORE_ADMIN_PASSWORD` 

Once logged for the first time, I land into the create project page. I create the Homelab project:
![Semaphore UI new project page](img/semaphore-create-project.png)

The first thing I want to do is to add a repository. In `Repository`, I click the `New Repository` button, and add my homelab repo URL. I don't specify credentials, the repo is public, you can find its mirror on Github [here](https://github.com/Vezpi/homelab):
![Semaphore UI new repository page](img/semaphore-add-repository.png)

In the the `Key Store`, I add the first credential, a SSH key for my user:
![Semaphore UI new key page](img/semaphore-create-new-ssh-key.png)

Before continue, I deploy 3 VMs

---
## Launching an Ansible playbook


---
## Deploy with Terraform


---
## Conclusion