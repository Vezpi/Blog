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

In my homelab, I like to play with tools like Ansible and Terraform. The primary interface is the CLI, which I love, but sometimes a fancy web UI is nicer.

After setting up my OPNsense cluster, I wanted a way to keep it up to date on a schedule. Automation means Ansible to me, but how do you automate and schedule playbooks?

At work I use Red Hat Ansible Automation Platform, which is great, but overkill for my lab. That’s how I found Semaphore UI. Let’s see what it can do.

---
## What is Semaphore UI

[Semaphore UI](https://semaphoreui.com/docs/) is a sleek web interface designed to run automation with tools like Ansible and Terraform, and even Bash, Powershell or Python scripts.

Initially began as Ansible Semaphore, a web interface created to provide a simple front-end for running solely Ansible playbooks. Over time the community evolved the project into a multi-tool automation control plane.

It is a self-contained Go application with minimal dependencies capable of using different database backend, such as PostgreSQL, MySQL, or BoltDB. 

---
## Installation

Semaphore UI supports several [installation](https://semaphoreui.com/docs/category/installation) methods: Docker, Kubernetes, package manager or simple binary file.

I used Docker for my setup, you can see how I currently deploy application in this [post]({{< ref "post/16-how-I-deploy-application" >}})

Here my `docker-compose.yml` file I've configured using PostgreSQL:
```yaml
services:
  semaphore:
    image: semaphoreui/semaphore:v2.16.45
    container_name: semaphore_ui
    environment:
      - TZ=Europe/Paris
      - SEMAPHORE_DB_USER=${POSTGRES_USER}
      - SEMAPHORE_DB_PASS=${POSTGRES_PASSWORD}
      - SEMAPHORE_DB_HOST=postgres 
      - SEMAPHORE_DB_PORT=5432 
      - SEMAPHORE_DB_DIALECT=postgres
      - SEMAPHORE_DB=${POSTGRES_DB}
      - SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
      - SEMAPHORE_ADMIN_PASSWORD=${SEMAPHORE_ADMIN_PASSWORD}
      - SEMAPHORE_ADMIN_NAME=${SEMAPHORE_ADMIN_NAME}
      - SEMAPHORE_ADMIN_EMAIL=${SEMAPHORE_ADMIN_EMAIL}
      - SEMAPHORE_ADMIN=${SEMAPHORE_ADMIN}
      - SEMAPHORE_ACCESS_KEY_ENCRYPTION=${SEMAPHORE_ACCESS_KEY_ENCRYPTION}
      - SEMAPHORE_LDAP_ACTIVATED='no'
      # - SEMAPHORE_LDAP_HOST=dc01.local.example.com
      # - SEMAPHORE_LDAP_PORT='636'
      # - SEMAPHORE_LDAP_NEEDTLS='yes'
      # - SEMAPHORE_LDAP_DN_BIND='uid=bind_user,cn=users,cn=accounts,dc=local,dc=shiftsystems,dc=net'
      # - SEMAPHORE_LDAP_PASSWORD='ldap_bind_account_password'
      # - SEMAPHORE_LDAP_DN_SEARCH='dc=local,dc=example,dc=com'
      # - SEMAPHORE_LDAP_SEARCH_FILTER="(\u0026(uid=%s)(memberOf=cn=ipausers,cn=groups,cn=accounts,dc=local,dc=example,dc=com))"
    depends_on:
      - postgres
    networks:
      - backend
      - web
    labels:
      - traefik.enable=true
      - traefik.http.routers.semaphore.rule=Host(`semaphore.vezpi.com`)
      - traefik.http.routers.semaphore.entrypoints=https
      - traefik.http.routers.semaphore.tls.certresolver=letsencrypt
      - traefik.http.services.semaphore.loadbalancer.server.port=3000
    restart: unless-stopped

  postgres:
    image: postgres:14
    hostname: postgres
    container_name: semaphore_postgres
    volumes:
     - /appli/data/semaphore/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    networks:
      - backend
    restart: unless-stopped

networks:
  backend:
  web:
    external: true
```

To generate the encrypting access keys, I use this command:
```bash
head -c32 /dev/urandom | base64
```

With Semaphore running, let’s take a quick tour of the UI and wire it up to a repo.

---
## Discovery

After starting the stack, I could reach the login page at the URL:
![Semaphore UI login page](img/semaphore-login-page.png)

To lo gin, I use the credentials defined by `SEMAPHORE_ADMIN_NAME`/`SEMAPHORE_ADMIN_PASSWORD`. 

On first login, Semaphore prompted me to create a project. I created the Homelab project:
![Semaphore UI new project page](img/semaphore-create-project.png)

The first thing I want to do is to add my *homelab* repository, you can find its mirror on Github [here](https://github.com/Vezpi/homelab). In `Repository`, I click the `New Repository` button, and add the repo URL. I don't specify credentials, the repo is public:
![Semaphore UI new repository page](img/semaphore-add-repository.png)

ℹ️ Before continue, I deploy 3 VMs for testing purpose: `sem01`, `sem02` and `sem03`. I deploy them using Terraform with [this project](https://github.com/Vezpi/Homelab/tree/main/terraform/projects/semaphore-vms).

To interact with these VMs I need to configure credentials. In the the `Key Store`, I add the first credential, a SSH key for my user:
![Semaphore UI new key page](img/semaphore-create-new-ssh-key.png)

Then I create a new `Inventory`. I'm using the Ansible inventory format (the only one available). I select the SSH key previously created and select the type as `Static`. In the fields I enter the 3 hosts created with their FQDN:
![Semaphore UI new inventory page](img/semaphore-create-new-static-inventory.png)

![Semaphore UI new inventory page](img/semaphore-create-new-static-inventory.png)

✅ Everything is now setup, I can move forward and test to run an Ansible playbook.

---
## Launching an Ansible playbook

I want to test something simple, install a web server with a custom page on these 3 VMs, I create the playbook `install_nginx.yml`:
```yaml
---
- name: Demo Playbook - Install Nginx and Serve Hostname Page
  hosts: all
  become: true

  tasks:
    - name: Ensure apt cache is updated
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present

    - name: Create index.html with hostname
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        content: |
          <html>
          <head><title>Demo</title></head>
          <body>
              <h1>Hostname: {{ inventory_hostname }}</h1>
          </body>
          </html>
        owner: www-data
        group: www-data
        mode: "0644"

    - name: Ensure nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
```

In Semaphore UI, I can now create my first `Task Template` for Ansible playbook. I give it a name, the playbook path (from the root folder of the repo), the repository and the branch:
![Semaphore UI new Ansible task template](img/semaphore-create-new-ansible-task-template.png)

Time to launch the playbook! In the task templates list, I click on the ▶️ button:
![Semaphore UI launch Ansible task template](img/semaphore-run-test-playbook.png)

The playbook launches and I can follow the output in real-time:
![Semaphore UI Ansible task output](img/semaphore-ui-ansible-task-output.png)

I can also check the results of previous runs:
![Semaphore UI tasks runs list](img/semaphore-ui-task-template-run-list.png)


✅ Finally I can confirm the job is done by checking the URL on port 80 (http):
![Testing URL after applying playbook on hosts ](img/semaphore-ui-test-nginx-page-playbook.png)

Managing the Ansible playbooks from Semaphore UI is pretty simple and really convenient. The interface is really sleek.

There are also a lot of customization available when setting the task template up. I can use variables in a survey, specify limit or tags. I really like it.


---
## Deploy with Terraform

While running Ansible playbooks was easy out of the box, this was a bit different to deploy with Terraform on Proxmox VE. Before starting, I destroy the 3 VMs deployed earlier.

Previously from the CLI, I was interacting on Terraform with the Proxmox cluster using a SSH key. I was not able to put it to work from Semaphore UI. I used a username with a password instead. 

I told myself it would be a good opportunity to use Ansible against my Proxmox nodes to create a dedicated user for this. But this didn't work, here the playbook I used:
```yaml
---
- name: Create Terraform local user for Proxmox
  hosts: nodes
  become: true
  tasks:
  
    - name: Create terraform user
      ansible.builtin.user:
        name: "{{ terraform_user }}"
        password: "{{ terraform_password | password_hash('sha512') }}"
        shell: /bin/bash

    - name: Create sudoers file for terraform user
      ansible.builtin.copy:
        dest: /etc/sudoers.d/{{ terraform_user }}
        mode: '0440'
        content: |
          {{ terraform_user }} ALL=(root) NOPASSWD: /sbin/pvesm
          {{ terraform_user }} ALL=(root) NOPASSWD: /sbin/qm
          {{ terraform_user }} ALL=(root) NOPASSWD: /usr/bin/tee /var/lib/vz/*
```

It was failing with the following error:
```plaintext
Unable to encrypt nor hash, passlib must be installed. No module named 'passlib'
```

It is apparently a known problem of Semaphore, to workaround, I installed `passlib` directly on the container
```bash
docker exec -it semaphore_ui pip install passlib
```

Finally I could create my user on the Proxmox nodes.

Next I create a variable group `pve_vm`. In a variable group I can define multiple variables and secrets together:
![Semaphore UI new variable group](img/semaphore-ui-create-variable-group.png)

Then I create a new task template, this time with the kind Terraform Code. I give it a name, the path of the terraform [project](https://github.com/Vezpi/Homelab/tree/main/terraform/projects/semaphore-vms), a workspace, the repository along with its branch and. the variable group:
![Semaphore UI new Terraform task template](img/semaphore-task-template-terraform.png)

Running the template gives me some additional options related to Terraform:
![Semaphore UI run Terraform task](img/semaphore-running-terraform-code-options.png)

After the Terraform plan, I'm proposed to apply, cancel or stop:
![Semaphore UI task Terraform plan](img/semaphore-terraform-task-working.png)

Finally after hitting ✅ to apply, I can see Terraform building the VM. This is exactly the same as using the CLI. At the end, my VMs are successfully deployed on Proxmox:
![Semaphore UI Terraform deploy complete](img/semaphore-ui-deploy-with-terraform.png)

---
## Conclusion

That's all for the tests with Semaphore UI, I hope this could help you to see what we can do with it.

Overall I think the interface is really nice. I can see myself using it for scheduling some Ansible playbooks. In the intro I was talking about update my OPNsense nodes, I would definitely do that!

For Terraform, I might use it to deploy some VMs to test something. I'd love to be able to use the HTTP backend for the tfstate, unfortunately it requires the PRO version.

To conclude, Semaphore UI is a great tool, really intuitive with a beautiful UI, good job!