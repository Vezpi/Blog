---
slug: create-nas-server-with-truenas
title: Template
description:
date:
draft: true
tags:
  - truenas
categories:
---
## Introduction

In my homelab, I need somewhere I can put datas, outside of my Proxmox VE cluster.

At the beginning, my only one physical server has 2 HDDs disks of 2 TB. When I installed Proxmox on it, these disks were still attached to the host. I managed to share the content using a NFS server in a LXC, but this was far from a good practice.

During this winter, the node started to fail, it was stopping by itself for no reason. This bad boy is 7 years old. When it was shut down, the NFS share were unavailable, which was affecting some services in my homelab. Luckily I could fix it up by replacing its CPU fan, but now I want a safer place for these datas.

I this article I will walk you through the entire build of my NAS, using TrueNAS.


## Choose the the right platform


For a while I wanted to have a NAS. Not one ready out-of-the-box like Synology or QNAP. While I think these are good products, I wanted to build mine. But I have a huge constraint of space in my tiny rack and the choice for a small NAS case are very limited.

### Hardware

I consider full flash NAS. This has several advantages:
- It is fast
- It is small
- It consumes less
- It heats less
But with a major drawback, the price.

While the speed is negligible to me because my network can't handle it, the others are exactly what I'm looking for. I don't need a massive volume a data, around 2 TB of usable space is enough.

My first choice was the [Aiffro K100](https://www.aiffro.com/fr/products/all-ssd-nas-k100). But I couldn't find a way to have it deliver in France without doubling the price. Finally I managed to buy a [Beelink ME mini](https://www.bee-link.com/products/beelink-me-mini-n150?variant=48678160236786).

This small cube has 2x 2.5Gbps Ethernet ports and can host up to 6x NVMe drives. I started with 2 drives for now, 2 TB each.



why truenas

## Install TrueNAS



## Configuration of TrueNAS
### basic conf
### pool creation

### dataset config

### data protection

## Use of TrueNAS

### Firewall rule

### Data migration

### Android application

## Conclusion