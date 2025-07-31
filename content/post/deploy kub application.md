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

---
## Helm

For these components to work, I will have to install new products. To install them, I will use Helm
### Why Helm
explain install Helm
### Install Helm


---
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

---
## Expose a `LoadBalancer` Service with BGP

At first, I was thinking of using **MetalLB** to expose the IP of my services to my home network. This is what I used in the past when I was using my ISP box as router. After reading this post, [Use Cilium BGP integration with OPNsense](https://devopstales.github.io/kubernetes/cilium-opnsense-bgp/), I could do it differently using **BGP** with my OPNsense router.
### What Is BGP?

BGP (Border Gateway Protocol) is a routing protocol used to exchange network routes between systems. In the Kubernetes homelab context, BGP allows your Kubernetes nodes to advertise IPs  directly to your **network router or firewall**. Your **router then knows** how to reach the IPs managed by your cluster.

So instead of MetalLB managing IP allocation and ARP replies, your nodes directly tell your router: “Hey, I own 192.168.1.240”.
### Legacy MetalLB Approach

Without BGP, MetalLB in Layer 2 mode works like this:
- Assigns a LoadBalancer IP (e.g., `192.168.1.240`) from a pool.
- One node responds to **ARP** for that IP on your LAN.

I know that MetalLB can also work with BGP, but what if my CNI (Cilium) can handle it out of the box?
### BGP with Cilium

With Cilium + BGP, you get:
- Cilium’s agent on the node advertises LoadBalancer IPs over BGP.
- Your router learns that IP and routes to the correct node.
- No need for MetalLB.

### BGP Setup

#### On OPNsense

#### In Cilium

### Deploying a LoadBalancer with BGP
#### Using an IP Address
#### Using a URL

---
## Kubernetes Ingress

TODO add why we need service  
### What is a Kubernetes Ingress

explain what is an Ingress and its purpose

### How Ingress Work


---
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

---
## Secure Connection with TLS

to use https

### Cert-Manager

#### Install Cert-Manager

install with helm
#### Setup Cert-Manager

verify clusterissuer

### Add TLS in an Ingress

ingress tls code

verify 

---
## Conclusion


