---
title: Deploy VM on Proxmox with Terraform
description: 
date: 2025-05-25
draft: true
tags:
  - terraform
  - proxmox
  - cloud-init
categories:
  - homelab
---
## Intro

In my homelab, one of the big project I had in mind was to be able to create my whole infrastructure using IaC and more precisely Terraform.

In this article I will show you how 
My first project is to create simple VM on [[Proxmox]] with Terraform, based of a [[cloud-init]] VM template

From LXC container
Add the link to the homelab GitHub repository

---
## What is Terraform?

Terraform is an open-source IaC tool developed by **HashiCorp**. It lets you define and provision infrastructure using a high-level configuration language called **HCL** (HashiCorp Configuration Language). With Terraform, you can manage cloud services, VMs, networks, DNS records, and more.

In my homelab, Terraform can simplify VM deployment and make my environment reproducible. You can define everything once in code and re-deploy it easily from scratch as will.

A quick mention of **OpenTofu**, it is a community-driven fork of Terraform that emerged after some licensing changes. It's almost fully compatible with Terraform and could be a great alternative down the line. But for now I still with Terraform.

---
## Proxmox Terraform Providers

To use Terraform, you’ll need a provider, a plugin that lets Terraform interact with your infrastructure, in the case of Proxmox, it will interact with the Proxmox API. There are currently two providers:
- [**Telmate/proxmox**](https://registry.terraform.io/providers/Telmate/proxmox/latest): One of the original providers. It’s widely used but not very actively maintained. It is simple to use and you can find many documentations of internet, but has limited features, with only 4 resources are available and no data sources: I couldn't get the node's resources for example.
- [**bpg/proxmox**](https://registry.terraform.io/providers/bpg/proxmox/latest): A newer and more actively developed provider, apparently developed by a single guy, with cleaner syntax and much wider resources support. It was harder to setup but I found it mature enough to work with it.

I chose the `bpg/proxmox` provider because it’s better maintained at the time of writing and I needed to retrieve nodes values, such as their hostname.

---
## Prepare the Environment

### Create a Cloud-init VM Template in Proxmox

Check out my previous article on [Proxmox - Create a Cloud-Init VM Template]({{< relref "post/proxmox-cloud-init-vm-template" >}}).

### Install Terraform

For the Terraform installation, I followed the [documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) to install it into my LXC container.

```bash
# Ensure that your system is up to date and you have installed the `gnupg`, `software-properties-common`, and `curl` packages installed. You will use these packages to verify HashiCorp's GPG signature and install HashiCorp's Debian package repository.
apt-get update && apt-get install -y gnupg software-properties-common

# Install the HashiCorp [GPG key](https://apt.releases.hashicorp.com/gpg).

wget -O- <https://apt.releases.hashicorp.com/gpg> | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# Verify the key's fingerprint.

gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint

# Add the official HashiCorp repository to your system. The `lsb_release -cs` command finds the distribution release codename for your current system, such as `buster`, `groovy`, or `sid`.

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] <https://apt.releases.hashicorp.com> $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Download the package information from HashiCorp.

apt update

# Install Terraform from the new repository.

apt-get install terraform
```

### Create a Dedicated Terraform User on Proxmox

Before Terraform can interact with your Proxmox cluster, you want to create a dedicated user with limited privileges. You could use the `root@pam` but I wouldn't recommended it for security perspectives.

From any of your Proxmox nodes, log into the console as priviledged user, `root` in that case.
1. **Create the Role `TerraformUser`**
```bash
pveum role add TerraformUser -privs "\
  Datastore.Allocate \
  Datastore.AllocateSpace \
  Datastore.Audit \
  Pool.Allocate \
  Sys.Audit \
  Sys.Console \
  Sys.Modify \
  VM.Allocate \
  VM.Audit \
  VM.Clone \
  VM.Config.CDROM \
  VM.Config.Cloudinit \
  VM.Config.CPU \
  VM.Config.Disk \
  VM.Config.HWType \
  VM.Config.Memory \
  VM.Config.Network \
  VM.Config.Options \
  VM.Console \
  VM.Migrate \
  VM.Monitor \
  VM.PowerMgmt \
  SDN.Use"
```

2. **Create the User `terraformer`**
```bash
pveum user add terraformer@pve --password <password>
```

3. **Assign the Role `TerraformUser` to the User `terraformer`**
```bash
pveum aclmod / -user terraformer@pve -role TerraformUser
```

4. **Create API token for the user `terraformer`**
```bash
pveum user token add terraformer@pve terraform -expire 0 -privsep 0 -comment "Terraform token"
```

⚠️ Copy and save the token given!

### Install SSH Keys on Proxmox Nodes



---
## Deploy your First VM
Show the code I used and explain each blocks

Add a link to the folder structure on Homelab repo on Github

```plaintext
terra/
├── config.toml
├── content/
│   └── posts/
│       └── hello-world.md
└── themes/
    └── PaperMod/
```

## Develop a Terraform Module
Explain how I transform my project into a reusable module

## Conclusion
Sum up what we realized and what are the next steps, use the module for my future project for kubernetes and associate it with Ansible