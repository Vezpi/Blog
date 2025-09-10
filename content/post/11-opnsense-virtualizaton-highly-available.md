---
slug: opnsense-virtualizaton-highly-available
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - proxmox
categories:
  - homelab
---
## Intro

I recently encountered my first real problem, my physical **OPNsense** box crashed because of a kernel panic, I've detailed what happened in that [post]({{< ref "post/10-opnsense-crash-disk-panic" >}})

After this event, I came up with an idea to enhance the stability of the lab: **Virtualize OPNsense**

This would require some modification at the network level and is quite critical to implement.