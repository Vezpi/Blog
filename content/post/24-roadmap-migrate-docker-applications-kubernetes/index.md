---
slug: roadmap-migrate-docker-applications-kubernetes
title: Roadmap of the Migration from Docker Compose to Kubernetes
description: Why I am moving my self-hosted applications from one Docker VM to Kubernetes and how I plan to do it.
date: 2026-09-27
draft: true
tags:
  - kubernetes
  - docker
categories:
  - homelab
---

## Intro

For years, my self-hosted applications have been running as Docker containers managed with Docker Compose on a single virtual machine. It works well enough, which is precisely what makes changing it slightly uncomfortable.

There is no urgent production incident forcing me to migrate. No mysterious outage, no hardware that is about to catch fire. I simply want to learn Kubernetes through hands-on experience and move my homelab to a platform that gives me more room to experiment.

😈 Yes, running a Kubernetes cluster for a homelab is overkill. I know. That is also the point.

This article is the roadmap for the migration, from the first cluster foundation work to eventually decommissioning the old Docker VM.

## Why Kubernetes in a homelab

The current Docker Compose setup is simple: one VM hosts the applications, and Compose describes how the containers should run. For a small self-hosted environment, that is a perfectly reasonable solution.

Kubernetes adds a considerable amount of complexity. There are multiple nodes, a control plane, networking, storage, ingress, certificates, monitoring, and backups to think about. I am not pretending this is the simplest way to host my services.

The motivation is learning. A homelab gives me a safe place to understand how Kubernetes behaves, test different approaches, and make mistakes without the constraints of a production environment. The goal is not to prove that Kubernetes is better than Docker Compose for every workload. The goal is to gain practical experience with Kubernetes.

There is another reason for doing this properly: I want the platform to become reproducible. Eventually, I want to build a disposable validation cluster, test changes there, and rebuild the cluster and its applications through automation using Terraform and Ansible.

## The migration strategy

I do not want to migrate everything in one massive operation. That would make troubleshooting needlessly difficult and would turn every small mistake into a potential service outage.

Instead, I am breaking the work into milestones. Each milestone adds an important capability to the platform before the next group of applications moves onto it.

The Kubernetes cluster itself is being bootstrapped manually at first. This is intentional. Before automating the process, I want to understand what happens during cluster creation and application deployment. GitOps is part of the end goal, but I am postponing it so I can first experience the platform without hiding the deployment process behind another layer of automation.

## Milestone 1: Build the cluster foundation

The first step is to create the infrastructure on which Kubernetes will run.

I plan to use Terraform to provision the virtual machines for the Kubernetes nodes. Ansible will then prepare those VMs. The initial cluster bootstrap and the installation of the Container Network Interface will be performed manually.

This approach gives me a useful separation:

- Terraform creates the machines.
- Ansible prepares the operating systems.
- The first Kubernetes bootstrap remains manual for learning purposes.

The cluster foundation needs to be reliable before applications become part of the picture. If the nodes and network are not healthy, debugging an application deployment becomes a particularly creative way of wasting an evening.

## Milestone 2: Add the entry point

Once the cluster exists, it needs a way to receive traffic. The next milestone is therefore the API gateway and certificate management.

I will deploy an API gateway and `cert-manager`, then deploy a first application to validate that the complete path works. This first application is not meant to represent a complete migration. It is a platform test: can an application be deployed, reached from outside the cluster, and secured with a certificate?

This milestone is important because it validates more than Kubernetes scheduling. It tests the integration between the cluster, networking, external access, and TLS.

## Milestone 3: Storage, backup, and monitoring

Before migrating anything important, I need to understand what happens to data.

The plan is to define storage classes for both Ceph and TrueNAS storage. I also need a baseline monitoring setup and a backup strategy for the cluster.

This is the point where the project stops being only about running containers. Stateless workloads are relatively easy to move. Stateful applications require decisions about where their data lives, how it is backed up, and how the service could be restored after a failure.

I do not want to discover that the backup story is incomplete after moving the applications that matter most.

## Milestones 4 to 6: Migrate applications gradually

With the platform capabilities in place, applications can move in groups based on their risk.

### Low-risk applications

The first migrations will be stateless applications. They are the best candidates for validating the deployment process because they do not carry critical data and should be easier to recreate.

### Medium-risk and stateful applications

Next come non-vital services and applications with more involved storage requirements. These migrations will help validate the storage classes, backups, and recovery procedures in a more realistic way.

### Critical applications

Vital applications come last. By then, the cluster should have already been exercised with less important workloads, and the monitoring and backup foundations should be more mature.

This ordering is deliberately conservative. The migration is also a learning project, but I do not need to turn every lesson into an outage.

## Milestone 7: Improve monitoring and disaster recovery

After the applications are migrated, the monitoring and backup solution will need another pass.

The initial setup is a baseline, not the final state. The goal is to move toward a more complete monitoring solution and implement a disaster recovery plan. A cluster can look healthy while still being difficult to recover, so the recovery process needs to be considered separately from day-to-day monitoring.

## Milestone 8: Automate the cluster lifecycle

The next major step is to make the platform disposable.

I want to be able to create a validation cluster from scratch and reliably rebuild both the cluster and its applications. Terraform and Ansible will be used to automate this process.

This is where the early manual work should pay off. By understanding the steps first, I can automate a process I actually understand instead of blindly converting commands into playbooks.

## Milestone 9: Introduce GitOps

Only after the platform and lifecycle automation are working will I introduce GitOps.

The repository will be reorganized to support that operating model, with the desired cluster and application state managed through Git. The objective is to enable a complete cluster deployment aligned with the GitOps strategy.

GitOps is the destination, not the starting line. Introducing it too early would make the first learning phase more difficult, especially while the cluster architecture and application deployment patterns are still changing.

## Milestone 10: Decommission the Docker VM

The final step is not a dramatic switch-off. I want to stop the Docker VM for a period of time while running the applications on Kubernetes. If everything remains stable and the new platform proves reliable, I can finally destroy the old VM.

Keeping the old environment available during the transition provides a safety net. It also gives me a clear definition of done: the migration is not complete merely because an application starts in Kubernetes. It is complete when I am confident enough to remove the previous platform.

## Conclusion

This is the biggest homelab project I have planned so far, and probably the most exciting one too.

The technical goal is to migrate self-hosted applications from a single Docker Compose VM to a Kubernetes cluster. The more important goal is to learn how to design, operate, automate, monitor, back up, and eventually rebuild that platform.

The roadmap deliberately moves from understanding to migration, then from migration to automation. I start with a manual cluster, add networking and storage, migrate applications by risk, improve recovery, automate the lifecycle, and finish with GitOps.

It is a lot of work for a homelab. That is exactly why it should be a great learning project.
