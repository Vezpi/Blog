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

After have created a Kubernetes cluster with `kubeadm` in [that post]({{< ref "post/8-create-manual-kubernetes-cluster-kubeadm" >}}), my next goal is to expose a simple pod externally, reachable with an URL and secured with a TLS certificate verified by Let's Encrypt.

To achieve that, I will need several components:
- Service
- Ingress
- Ingress Controller
- TLS Certificates

###