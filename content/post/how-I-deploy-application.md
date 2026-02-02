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

In this post, I am not going to explain best practices for deploying applications. Instead, I want to document how I am currently deploying new applications in my homelab.

Think of this article as a snapshot in time. This is how things really work today, knowing that in the near future I would like to move toward a more GitOps-oriented workflow.

The method I use is fairly simple. I have tried to standardize it as much as possible, but it still involves quite a few manual steps.  I will also explain how I update applications, which is, in my opinion, the biggest weakness of this setup. As the number of applications keeps growing, keeping everything up to date requires more and more time.

---
## Platform Overview

Before diving into the workflow, here is a quick overview of the main components involved.
### Docker

Docker is the foundation of my application stack. Whenever possible, I deploy applications as containers.

I have been using Docker Compose for years. At the time, everything was running on a single physical server. Today, my setup is VM-based, and I could migrate to Docker Swarm, but I have chosen not to. It might make sense in some scenarios, but it is not aligned with where I want to go long term.

For now, I still rely on a single VM to host all Docker applications. This VM is more or less a clone of my old physical server, just virtualized.

### Proxmox

All my VMs are hosted on a Proxmox cluster.

The cluster is composed of three nodes and uses Ceph as a distributed storage backend. This gives me high availability and makes VM management much easier, even though the Docker workloads themselves are not highly distributed.

### Traefik

Traefik runs directly on the Docker host and acts as the reverse proxy.

It is responsible for routing HTTP and HTTPS traffic to the correct containers and for managing TLS certificates automatically using Let’s Encrypt. This keeps application-level configuration simple and centralized.

### OPNsense

OPNsense is my router, firewall and also acts as reverse proxy.

Incoming HTTPS traffic is forwarded to Traefik using the Caddy plugin with Layer 4 rules. TLS is not terminated at the firewall level. It is passed through to Traefik, which handles certificate issuance and renewal.

### Gitea

Gitea is a self-hosted Git repository, I have one instance running in my homelab.

Inside Gitea, I have a private repository that contains all my Docker Compose configurations. Each application has its own folder, making the repository easy to navigate and maintain.

---
## Deploy New Application

To standardize deployments, I use a `docker-compose.yml` template that looks like this:
```yml
services:
  NAME:
    image: IMAGE
    container_name: NAME
    volumes:
      - /appli/data/NAME/:/
    environment:
      - TZ=Europe/Paris
    networks:
      - web
    labels:
    - traefik.enable=true
    - traefik.http.routers.NAME.rule=Host(`HOST.vezpi.com`)
    - traefik.http.routers.NAME.entrypoints=https
    - traefik.http.routers.NAME.tls.certresolver=letsencrypt
    - traefik.http.services.NAME.loadbalancer.server.port=PORT
    restart: always

networks:
  web:
    external: true
```

Let me explain.

For the image, depending on the application, the registry used could differ, but I still the Docker Hub by default. When I try a new application, I might use the `latest` tag at first. Then if I choose to keep the it, I prefer to pin the current version instead of `latest`.

I use volume binds for everything stateful. Every application got its own folder in the `/appli/data` filesystem.

When an application needs to be reachable with HTTPS, I link the container serving the requests in the `web` network, which is managed by Traefik and I associate it labels. The `entrypoint` and `certresolver` is defined in my Traefik configuration. The URL defined in `Host()` is the one which will be used to access the application. This needs to be the same as defined in the Layer4 route in the Caddy plugin of OPNsense. 

If several containers need to talk to each other, I add a `backend` network which will be created when the stack will be deployed, dedicated for the application. This way, no ports need to be opened on the host.

### Steps to Deploy

Most of the work is done from **VScode**:
- Create a new folder in that repository, with the application name.
- Copy the template above inside this folder.
- Adapt the template with the values given by the application documentation.
- Create a `.env` file for secrets if needed. This file is ignored by `.gitignore`.
- Start the services directly from VS Code using the Docker extension.


Then in the **OPNsense** WebUI, I update 2 Layer4 routes for the Caddy plugin:
- Depending if the application should be exposed on the internet or not, I have an *Internal* and *External* route. I add the URL given to Traefik in one of these.
- I also add this URL in another route to redirect the Letsencrypt HTTP challenge to Traefik.

Once complete, I test the URL. If everything is configured correctly, the application should be reachable over HTTPS.

When everything works as expected, I commit the new application folder to the repository.

---
## Update Application

Application updates are still entirely manual.

I do not use automated tools like Watchtower for now. About once a month, I check for new versions by looking at Docker Hub, GitHub releases, or the application documentation.

For each application I want to update, I review:
- New features
- Breaking changes
- Upgrade paths if required

Most of the time, updates are straightforward:
- Bump the image tag in the Docker Compose file
- Restart the stack.
- Verify that the containers restart properly
- Check Docker logs
- Test the application to detect regressions

If everything works, I continue upgrading step by step until I reach the latest available version. Once done, I commit the changes to the repository.

---
## Pros and Cons

### Pros

- Simple model, one VM, one compose file per application.
- Traefik automates TLS and routing with minimal boilerplate.
- Everything declarative enough to rebuild quickly from the repo.
- Easy to debug: logs and Compose files are local and transparent.

### Cons

- Manual updates don’t scale as the app count grows.
- Single Docker VM is a single point of failure.
- Secrets in .env are convenient but basic; rotation and audit are manual.
- No built‑in rollbacks beyond “change the tag back and redeploy.”

---
## Conclusion

This setup works, and it has served me well so far. It is simple and intuitive. However, it is also very manual, especially when it comes to updates and long-term maintenance.

As the number of applications grows, this approach clearly does not scale very well. That is one of the main reasons why I am looking toward GitOps and more declarative workflows for the future.

For now, though, this is how I deploy applications in my homelab, and this post serves as a reference point for where I started.