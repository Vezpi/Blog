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
@Explain briefly OPNsense

Incoming HTTPS traffic is forwarded to Traefik using the Caddy plugin with Layer 4 rules. TLS is not terminated at the firewall level. It is passed through to Traefik, which handles certificate issuance and renewal.

### Gitea

I host a Gitea server in my homelab.

Inside Gitea, I have a private repository that contains all my Docker Compose configurations. Each application has its own folder, making the repository easy to navigate and maintain.

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

For the image, depending on the application, the registry used could differ, but I still the Docker Hub by default. When I try a new application, I might use  the `latest` at start. Then if I choose to keep the application, I prefer to pin the version instead of `latest`.


Steps to deploy a new application:
From VScode:
- I create a new folder in that repository
- I copy the template file inside this folder
- I adapt the template with the values given by the application documentation
- I try to avoid using the latest tag for the images
- Eventually I create a .env file to store secrets which is ignored by the .gitignore of the repo
- If volumes are needed, I use bind mounts on a specific FS on the server
- I run the services directly from VScode using a Docker extension
From OPNsense
- In the Caddy plugin, I update 2 Layer4 routes:
	- Depending if the application should be exposed on the internet or not, I have an Internal or External route. I add the URL given to Traefik in one of these.
	- I also add this URL in another route to redirect the HTTP challenge to Traefik

Finally I test the URL and it should work!
Once everything work as expected, I commit the new folder on the repo
## Update Application

Updating my applications is still manual to me. I don't use tools like Watchtower for now. Every month or so, I check for new versions. I check on the Docker hub, GitHub or on the application documentation.

For each of the application I want to uppdate, I look for new features, breaking changes and try to bump them to the latest version.

Most of the time, updating an application is straightforward. I update the image tag and restart the docker compose stack. Then I verify if the application restart properly, check the docker logs and test the application to detect any regression.

If the tests are successful I continue to update until I reach the latest version available. Once reached, I commit the update in the repository.


## Conclusion

Using Docker 