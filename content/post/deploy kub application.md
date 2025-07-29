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

After have created a Kubernetes cluster in my homelab with `kubeadm` in [that post]({{< ref "post/8-create-manual-kubernetes-cluster-kubeadm" >}}), my next goal is to expose a simple pod externally, reachable with an URL and secured with a TLS certificate verified by Let's Encrypt.

To achieve that, I will need several components:
- Service: TODO add oneline description
- Ingress: TODO add oneline description
- Ingress Controller: TODO add oneline description
- TLS Certificates: TODO add oneline description

For these components to work, I will have to install new products. To install them, I will use Helm
## Helm

### Install Helm
explain install Helm

## Services

TODO add why we need service  

### What is a Kubernetes Service

### Different Kubernetes Services
#### ClusterIP
#### NodePort
#### LoadBalancer
## Expose a LoadBalancer Service with BGP

### What is BGP

#### Traditional MetalLB Approach

#### BGP with Cilium

### Enable BGP

#### Enable BGP in OPNsense

#### Enable BGP in Cilium

### Provisioning Your First LoadBalancer with BGP
#### Using an IP Address
#### Using a URL

## Ingress

TODO add why we need service  
### What is a Kubernetes Ingress

### How Ingress Work

## Ingress Controller

### What is an Ingress Controller

### Which Ingress Controller to Use

### Install NGINX Ingress Controller

### Associate a Service to an Ingress

### Use HTTPS

## TLS Certificate

secretariat.sogecer@