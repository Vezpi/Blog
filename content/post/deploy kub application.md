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

## Kubernetes Services

TODO add why we need service  

### What is a Kubernetes Service

explain what is a Service and its purpose
### Different Services

give the list of differents services
#### ClusterIP

explain what ClusterIP services are
#### NodePort

explain what NodePort services are
#### LoadBalancer

explain what LoadBalancer services are
## Expose a LoadBalancer Service with BGP

explain that

### What is BGP

explain BGP
#### Traditional MetalLB Approach

previous approach

#### BGP with Cilium

### Enable BGP

#### Enable BGP in OPNsense

#### Enable BGP in Cilium

### Provisioning Your First LoadBalancer with BGP
#### Using an IP Address
#### Using a URL

## Kubernetes Ingress

TODO add why we need service  
### What is a Kubernetes Ingress

explain what is an Ingress and its purpose

### How Ingress Work

## Ingress Controller

### What is an Ingress Controller

explain what is an Ingress Controller and its purpose

### Which Ingress Controller to Use

comparison between ingress controller
which one I picked and why
### Install NGINX Ingress Controller

detail installation of NGINX Ingress Controller
verify ingress controller service
### Associate a Service to an Ingress



oneline to explain how to use https

## TLS Certificate





