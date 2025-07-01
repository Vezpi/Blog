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

Here I want to detail how to transform this piece of code in a reusable Terraform module. I will then show you how to modify your code to make use of it in other projects.

---
## What is a Terraform Module?

Terraform modules are reusable components that let you organize and simplify your infrastructure code by grouping related resources into a single unit. Instead of repeating the same configuration across multiple places, you can define it once in a module and use it wherever needed, just like calling a function in programming.

Modules can be local (within your project) or remote (from the Terraform Registry or a Git repository), making it easy to share and standardize infrastructure patterns across teams or projects. By using modules, you make your code more readable, maintainable, and scalable.

---
## Transform Project into Module

We will now transform the Terraform code from the [previous project]({{< ref "post/3-terraform-create-vm-proxmox" >}}) by creating our own module called `pve_vm`.

> 📌 Reminder, you can find all the code I have written in my [Homelab repo](https://git.vezpi.me/Vezpi/Homelab/), the following code is located [here](https://git.vezpi.me/Vezpi/Homelab/src/commit/22f64034175a6a4642a2c7b6656688f16ece5ba1/terraform/projects/simple-vm). Don't forget to match your variables with your environment!

### Code Structure

Our module will live next to our projects, in another folder:
```plaintext
terraform
`-- modules
    `-- pve_vm
        |-- main.tf
        |-- provider.tf
        `-- variables.tf
```

### Module's Code

Basically, the module files are those from the project we are transforming. I just kept out the parts related to the proxmox cluster, which will stay at the project level.

The module `pve_vm` will be decomposed in 3 files:
- **main**: The core logic
- **provider**: The providers needed to function
- **variables**: The variables of the module

#### `main.tf`

```hcl
data "proxmox_virtual_environment_vms" "template" {
  filter {
    name   = "name"
    values = ["${var.vm_template}"]
  }
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name
  source_raw {
    file_name = "${var.vm_name}.cloud-config.yaml"
    data      = <<-EOF
    #cloud-config
    hostname: ${var.vm_name}
    package_update: true
    package_upgrade: true
    packages:
      - qemu-guest-agent
    users:
      - default
      - name: ${var.vm_user}
        groups: sudo
        shell: /bin/bash
        ssh-authorized-keys:
          - "${var.vm_user_sshkey}"
        sudo: ALL=(ALL) NOPASSWD:ALL
    runcmd:
      - systemctl enable qemu-guest-agent 
      - reboot
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.node_name
  tags      = var.vm_tags
  agent {
    enabled = true
  }
  stop_on_destroy = true
  clone {
    vm_id     = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    node_name = data.proxmox_virtual_environment_vms.template.vms[0].node_name
  }
  bios    = var.vm_bios
  machine = var.vm_machine
  cpu {
    cores = var.vm_cpu
    type  = "host"
  }
  memory {
    dedicated = var.vm_ram
  }
  disk {
    datastore_id = var.node_datastore
    interface    = "scsi0"
    size         = 4
  }
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
    datastore_id      = var.node_datastore
    interface         = "scsi1"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
  network_device {
    bridge  = "vmbr0"
    vlan_id = var.vm_vlan
  }
  operating_system {
    type = "l26"
  }
  vga {
    type = "std"
  }
  lifecycle {
    ignore_changes = [
      initialization
    ]
  }
}

output "vm_ip" {
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses[1][0]
  description = "VM IP"
}
```

#### `provider.tf`

```hcl
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
```

#### `variables.tf`

> ⚠️ The defaults are based on my environment, adapt them to yours.

```hcl
variable "node_name" {
  description = "Proxmox host for the VM"
  type        = string
}

variable "node_datastore" {
  description = "Datastore used for VM storage"
  type        = string
  default     = "ceph-workload"
}

variable "vm_template" {
  description = "Template of the VM"
  type        = string
  default     = "ubuntu-cloud"
}

variable "vm_name" {
  description = "Hostname of the VM"
  type        = string
}

variable "vm_user" {
  description = "Admin user of the VM"
  type        = string
  default     = "vez"
}

variable "vm_user_sshkey" {
  description = "Admin user SSH key of the VM"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID62LmYRu1rDUha3timAIcA39LtcIOny1iAgFLnxoBxm vez@bastion"
}

variable "vm_cpu" {
  description = "Number of CPU cores of the VM"
  type        = number
  default     = 1
}

variable "vm_ram" {
  description = "Number of RAM (MB) of the VM"
  type        = number
  default     = 2048
}

variable "vm_bios" {
  description = "Type of BIOS used for the VM"
  type        = string
  default     = "ovmf"
}

variable "vm_machine" {
  description = "Type of machine used for the VM"
  type        = string
  default     = "q35"
}

variable "vm_vlan" {
  description = "VLAN of the VM"
  type        = number
  default     = 66
}

variable "vm_tags" {
  description = "Tags for the VM"
  type        = list(any)
  default     = ["test"]
}
```


##  Deploy a VM Using our Module

Now that we've moved all the resources required to deploy our VM into the `pve_vm` module, our project folder only needs to call that module and provide the necessary variables.

### Code Structure

For clarity, I've separated the modules and the projects:
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

### Project's Code

In this example, I manually provide the values when calling my module, the others are related to the cluster 
#### `main.tf`

```hcl
module "pve_vm" {
  source            = "../../modules/pve_vm"
  node_name         = "zenith"
  vm_name           = "zenith-vm"
  vm_cpu            = 2
  vm_ram            = 2048
  vm_vlan           = 66
}

output "vm_ip" {
  value = module.pve_vm.vm_ip
}
```

#### `provider.tf`

```hcl
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = false
  ssh {
    agent       = false
    private_key = file("~/.ssh/id_ed25519")
    username    = "root"
  }
}
```

#### `variables.tf`

```hcl
variable "proxmox_endpoint" {
  description = "Proxmox URL endpoint"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}
```