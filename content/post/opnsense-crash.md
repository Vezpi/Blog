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

This week, I experienced my first real problem on my homelab, which caused my whole home network to go down. 

My OPNsense router crashed and after trying to recover , I finally had to reinstall it from scratch and restore almost all the configuration, thanks to a single XML file.

In that story, I will try to explain how 

## The Calm Before the Storm

My OPNsense setup before the incident

Confidence in my homelab

## The Unexpected Reboot

How I first noticed something was wrong

The kernel panic that started it all

## First Troubleshooting Attempts

Caddy refusing to start

Digging into logs and finding corrupted certs

Quick fixes to restore services

## Filesystem Corruption

Upgrade attempt from 25.1 to 25.7 gone wrong

pkg errors and a broken package database

Discovering the dirty filesystem with fsck

## When Things Got Worse

Broken bootstrap and missing core components

Realizing the system was half-upgraded and unstable

The tough decision: reinstall vs. repair

## Starting Over the Hard Way

Pulling the box out of the rack

Preparing the installer USB

Fresh install of OPNsense 25.7

## The Lifesaver: config.xml

Copying my configuration from backup

Restoring the system to its former self

Which services came back instantly

Which ones didn’t (goodbye UniFi controller backup…)

## Lessons Learned the Hard Way

What I did wrong (and why it hurt)

What I should have done differently

The single most important file in OPNsense

Why keeping off-box backups matters

## Moving Forward

My new backup strategy

Plans to improve reliability in my homelab

Final thoughts: sometimes starting fresh is the cleanest fix

## Conclusion

How this failure taught me more than a normal upgrade ever could

Encouragement for others to prepare before disaster strikes