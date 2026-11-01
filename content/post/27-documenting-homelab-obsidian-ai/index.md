---
slug: documenting-homelab-obsidian-ai
title: Documenting My Homelab in Obsidian with AI
description: How I use Obsidian and an AI-led interview to document my homelab, giving my agents precise context they can help keep up to date.
date: 2026-11-01
draft: true
tags:
  - obsidian
  - ai
categories:
  - homelab
image: ""
---

## Intro

I have been using Obsidian for about three years now, after moving from Notion. It holds my notes and project documentation, but it is also where I write the articles for this blog.

With AI agents joining my homelab workflow, those notes have another use. An agent helping me with a project needs to understand the infrastructure it is working with. Knowing how Proxmox or Docker works is useful, but that does not tell it how I use them at home.

I need to give it that context. For my homelab inventory, I start by giving an agent broad information about the lab, then ask it to interview me and write the documentation from my answers.

The agent gets to ask the questions and take the notes. I still have to know what is plugged into what. 😅

## Why Obsidian fits

[Obsidian](https://obsidian.md/) is a note-taking application that stores notes as Markdown files in a local folder called a vault. Notes can link to each other, so a page about an application can lead to its VM, storage, or related project.

The files are ordinary text files. I can read and edit them in Obsidian, track them with Git, and let an AI agent work on them using file tools. The agent does not need to operate the Obsidian interface to update a note.

In my setup, the vault is versioned in my self-hosted Gitea instance. That gives documentation changes a history I can inspect, including changes made by an agent.

📖 The same vault contains my blog source, but that does not make the whole vault public. The publishing workflow synchronizes the dedicated `Blog/` folder to the Hugo blog repository. My homelab inventory and private notes stay outside that content selection. I describe that pipeline in [Blog Deployment featuring Obsidian, Hugo and Gitea Actions]({{< ref "post/2-blog-deployment-obisidan-hugo-gitea-actions" >}}).

## An interview instead of a blank page

I give the agent a broad description of the infrastructure, then ask it to interview me to fill in the details. Its job is to turn that starting information and my answers into structured inventory notes.

That changes the work I need to do. Rather than writing every note from scratch and deciding how to organize it, I answer focused questions about the setup. The agent handles the writing and links the related components together.

I prefer to go through one item at a time. A large questionnaire would mostly give me another document to finish. A focused question is easier to answer, and if I am unsure about a detail, we can leave it for verification rather than make something up.

The review leaves a visible record of those gaps. Some details are confirmed, while others remain explicitly unverified. An unused application, for example, is not necessarily a stopped or removed container. That distinction belongs in the notes until I check it.

⚠️ A confident sentence is not evidence. Asking me a follow-up question is much more useful than silently completing the infrastructure with something plausible.

## A linked inventory

The inventory lives under `Homelab/Inventory/`, organized into four categories:

- Compute covers physical hosts, VMs, LXCs, and cluster overviews. Examples include my Proxmox cluster, the `dockerVM` application VM, and the `bastion` management LXC.
- Storage describes the storage platforms, such as Ceph and TrueNAS.
- Network covers connectivity and shared network services, with notes for OPNsense, VLANs, DNS, DHCP, and UniFi.
- Application contains one note per application, such as Home Assistant, Gitea, and Portainer.

An `Infrastructure.md` index links to the component notes and gives me, or an agent, somewhere to start.

Each component has a dedicated note. The notes follow the same structure, with a description, technical details, relations, and a dated changelog. Their properties describe the type of component, its operational status, where it runs, and what it depends on.

Two properties are particularly useful:

| Property | What it describes |
| --- | --- |
| `runs_on` | The host or platform on which the component runs |
| `depends_on` | Other services or infrastructure it needs beyond that host |

### A complete note

Here is the full `Portainer.md` inventory note. It is short enough to show the whole structure, including the YAML properties and the changelog:

```markdown
---
type: inventory
kind: application
status: active
runs_on:
  - "[[dockerVM]]"
depends_on:
  - "[[Traefik]]"
  - "[[Inventory/Network/OPNsense|OPNsense]]"
managed_by: manual
high_availability: false
tags:
  - inventory
  - docker
  - portainer
---
### Description

Docker management UI for the [[dockerVM]] application stack. Provides visual container management, logs, and monitoring for Docker Compose workloads.

### Details

| Property | Value |
|----------|-------|
| Runs on | [[dockerVM]] (Docker Compose) |
| Purpose | Visual Docker management |

### Relations

- **Managed**: All Docker containers on [[dockerVM]].
- **Ingress**: Via [[Traefik]] → [[Inventory/Network/OPNsense|OPNsense]] HAProxy.

### Changelog

- **2026-10-12**: Initial documentation.
- **2026-10-16**: Removed the host from `depends_on`; it is represented by `runs_on`.
```

The double brackets are Obsidian links, shown here as literal Markdown rather than links on the blog. They connect Portainer to its host and ingress dependencies. The changelog also records a correction to that relationship: the VM belongs in `runs_on`, without duplicating it in `depends_on`.

For example, my Home Assistant note points to `dockerVM` as its host. The VM note then describes the primary Docker Compose application stack and its relationship to the Proxmox cluster and Ceph storage. Related application notes explain the roles of Node-RED and InfluxDB.

An agent can follow those links when a task needs more context. It does not have to treat every application as an isolated container, or read the entire vault before answering a question.

The inventory also separates the current setup from planned work. My Kubernetes foundation is deployed, but the primary application stack still runs on Docker Compose. A migration project is not proof that the applications have already moved.

## Context the agents can maintain

💡 This is what makes the inventory useful beyond documentation. It gives my agents a shared, precise reference for the homelab, instead of relying on whatever each agent remembers from an earlier conversation.

Before helping with an application, an agent can consult its inventory note and follow the relevant dependencies. Project notes explain the work and decisions around a change. The inventory describes the current state. Both are useful, but they answer different questions.

The next part is keeping that context current. I want the agents to maintain the documentation they use, updating the relevant notes as verified changes happen rather than leaving me with a separate writing task every time.

Later, I want the agents to verify facts against the infrastructure by gathering data directly from the components. With appropriate read-only access, they could compare what is actually running with what the inventory says, flag differences, and help correct outdated notes. That is a future step, not an automatic verification process already in place.

For now, the agents need confirmed information, whether it comes from my answers or an authorized investigation. I remain responsible for deciding and applying infrastructure changes. Reading data to verify a note is a different responsibility from changing the system it describes.

Git history and the inventory changelogs make those documentation updates reviewable. Unknown details should stay marked as unknown, and planned changes should stay separate from deployed ones.

## Conclusion

The inventory already gives my agents a documented starting point for understanding the lab. Building it through an interview lets me provide the information while the agent handles the structure and writing.

I want to carry that approach into maintenance: agents reading the inventory before they work, then helping update it from verified results. Obsidian gives me a familiar place to review those notes, and Markdown gives the agents files they can work with directly.

I still need to check the facts. At least I can share the note-taking.
