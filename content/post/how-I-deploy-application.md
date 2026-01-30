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

In this post, I'm not gonna tell you what are the good practices. I just want to point out how I'm deploying new application in my homelab.

The idea is to make a kind of testimony, that at this point in time, I was doing that way.

This is method is quite simple but involve quite a lot of manual operations
## Current Platform


### Docker
I deploy using Docker whenever it is possible
I use a VM in my Proxmox cluster

### Proxmox
Proxmox cluster composed of 3 nodes, highly available with a Ceph distributed storage

### Traefik
Traefik is installed on the docker host to manage the HTTPS connections

### OPNsense
On the fronted, there is an HA OPNsense cluster which redirect the HTTPS connections to Traefik using a Caddy plugin. TLS is not terminated by Caddy but only passed through to Traefik which manages the TLS certificates automatically.

## Deploy New Application

In my homelab, I host a Gitea server. Inside I have a private repository where I host the docker compose configurations for my applications

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

Updating my applications is done manually. I don't use tools like Watchtower for now. Every month or so, I check for new versions. It could be on the Docker hub, GitHub or on the application documentation.

For each of the application, I look for new features, breaking changes and try to bump them to the latest version.

Most of the time, updating an application is straightforward. I update the image tag and restart the docker compose stack. Then I verify if the application restart properly, check the docker logs and test the application to detect any regression.

If the tests are successful I continue to update until I reach the latest. Once reached, I commit the update in the repository.


## Conclusion