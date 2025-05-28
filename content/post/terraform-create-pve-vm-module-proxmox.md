---
slug: 
title: Template
description: 
date: 
draft: true
tags: 
categories:
---
## Develop a Terraform Module

In the final step of this article, I will show you how you can transform this piece of code in a reusable Terraform module.

### What is a Terraform Module?

Terraform modules are reusable components that let you organize and simplify your infrastructure code by grouping related resources into a single unit. Instead of repeating the same configuration across multiple places, you can define it once in a module and use it wherever needed, just like calling a function in programming.

Modules can be local (within your project) or remote (from the Terraform Registry or a Git repository), making it easy to share and standardize infrastructure patterns across teams or projects. By using modules, you make your code more readable, maintainable, and scalable.

### Terraform Code

We will now transform the Terraform code above by creating our own module called `pve_vm

> 📌 Reminder, you can find all the code I have written in my [Homelab repo](https://git.vezpi.me/Vezpi/Homelab/), the following code is located [here](https://git.vezpi.me/Vezpi/Homelab/src/commit/22f64034175a6a4642a2c7b6656688f16ece5ba1/terraform/projects/simple-vm). Don't forget to match your variables with your environment!
#### Code Structure

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

#### Module

