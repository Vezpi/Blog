---
slug: 
title: Create a Terraform module for Proxmox
description: 
date: 
draft: true
tags: 
categories:
---
## Intro

In one of my [previous article]({{< ref "post/3-terraform-create-vm-proxmox" >}}), I explained how to deploy Virtual Machines on Proxmox using Terraform from scratch.

Here I want to detail how to transform this piece of code in a reusable Terraform module. I will then show you how to modify your code to make use of it.

---
## What is a Terraform Module?

Terraform modules are reusable components that let you organize and simplify your infrastructure code by grouping related resources into a single unit. Instead of repeating the same configuration across multiple places, you can define it once in a module and use it wherever needed, just like calling a function in programming.

Modules can be local (within your project) or remote (from the Terraform Registry or a Git repository), making it easy to share and standardize infrastructure patterns across teams or projects. By using modules, you make your code more readable, maintainable, and scalable.

---
## Transform Project into Module

We will now transform the Terraform code from the [previous project]({{< ref "post/3-terraform-create-vm-proxmox" >}}) by creating our own module called `pve_vm`.

> 📌 Reminder, you can find all the code I have written in my [Homelab repo](https://git.vezpi.me/Vezpi/Homelab/), the following code is located [here](https://git.vezpi.me/Vezpi/Homelab/src/commit/22f64034175a6a4642a2c7b6656688f16ece5ba1/terraform/projects/simple-vm). Don't forget to match your variables with your environment!

### Code Structure

Our module will live next to our project, in another folder:
```plaintext
terraform
|-- modules
|   `-- pve_vm
|       |-- main.tf
|       |-- provider.tf
|       `-- variables.tf
`-- projects
    `-- simple-vm-with-module
        |-- credentials.auto.tfvars
        |-- main.tf
        |-- provider.tf
        `-- variables.tf
```

### Module

The module `pve_vm` will be decomposed in 3 files:
- **main**: The core logic
- **provider**: The providers needed to function
- **variables**: The variables of the module

