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

In this post, I'm not gonna tell you what are the good practices to deploy applications. Instead, I just want to point out how, currently, I'm deploying new application in my homelab.

The idea is to make a kind of statement, that at this point in time, I was doing that way. Because ideally, in a near future, I'd adopt GitOps

This method is quite simple, I've tried to industraliaze it but still require quite a lot of manual operations. Also I'll show you how I update them, which is to me the biggest flaw. As my application pool keeps growing, it requires me more time to keep up.

## Platform Overview

Let me break down the principal components involved:
### Docker
(Explain briefly Docker)

I deploy using Docker whenever it is possible.

I'm using Docker compose for years now. At this time I only had a single server. Now I'm using VMs and I could migrate to a Docker Swarm, but I didn't. It might be a good idea, but this is not what I plan to do for the future.
For the moment, I still use a single VM to host my Docker applications, which is more or less a clone of my old physical server.

### Proxmox
(Explain briefly Proxmox)

My VM is hosted on my Proxmox cluster
Proxmox cluster composed of 3 nodes, highly available with a Ceph distributed storage

### Traefik
(Explain briefly Traefik)

Traefik is installed on the docker host to manage the HTTPS connections

### OPNsense
(Explain briefly OPNsense)

On the fronted, there is an HA OPNsense cluster which redirect the HTTPS connections to Traefik using a Caddy plugin. TLS is not terminated by Caddy but only passed through to Traefik which manages the TLS certificates automatically.

### Gitea
(Explain briefly Gitea)

In my homelab, I host a Gitea server. Inside I have a private repository where I host the docker compose configurations for my applications

## Deploy New Application

I have a template docker-compose.yml which looks like this:
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