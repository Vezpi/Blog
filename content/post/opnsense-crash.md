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

My OPNsense router crashed and after trying to recover , I finally had to reinstall it from scratch and restore almost all the configuration, thanks to a single XML file. In that story, I will tell you what happened, what I did to recover and what I shouldn't have done.

This kind of exercise is the worst thing you want to happen because it's never funny to have everything go boom, but this is, by far, the best way to learn.

## The Calm Before the Storm

My OPNsense box had been running smoothly for months. Router, firewall, DNS, DHCP, VLANs, VPN, reverse proxy and even UniFi controller, all the pieces of my homelab network ran through it, but not only, it is also serving internet at home.

This is the heart of my network, I barely can't do anything without it now. I have detailed how this is working in my [Homelab]({{< ref "page/homelab" >}}) section. It was “just working,” and I wasn’t worried about it. I felt confident, its backup was living only inside the machine...

Maybe too confident.

## The Unexpected Reboot

Out of nowhere, the box rebooted by itself just before midnight. By chance, I was just passing by my rack on my way to bed. I knew the box rebooted because I heard its little beep it is doing when the machine start.

I wondered why the router restarted without my will. In my bed, I quickly checked if internet was working, and it was. But none of my services were available, my home automation or even this blog. I was tired, I would fix that the next day...

In the morning, looking at the logs, I found the culprit
```
panic: double fault
```

A kernel panic. My router had literally crashed at the hardware level.

## First Troubleshooting Attempts

At first, the impact seemed minor. Only one service wasn’t coming back up: Caddy, my reverse proxy. That was making sense if my services weren't available.

Digging into the logs, I found the error:

```
caching certificate: decoding certificate metadata: unexpected end of JSON input
```

It turned out that one of the cached certificates had been corrupted during the crash. Deleting its cache folder fixed Caddy, and suddenly all my HTTPS services were back online.

I thought I had dodged the bullet. I didn't investigate much on the root cause analysis, the kernel logs were polluted by one of the interfaces flapping, I thought it was just a bug, instead, I checked for any updates, my first mistake.

My OPNsense instance was in version 25.1, and the newer 25.7 was available. Let's upgrade it, yay!

The upgrade rolled out successfully, but something was wrong. When I tried to look for any update, I saw a corruption in `pkg`, the package manager database:
```
pkg: sqlite error while executing iterator in file pkgdb_iterator.c:1110: database disk image is malformed
```

🚨 My internal alarm sensor triggered, I wondered about backups, I immediately decided to download the latest backup:
![Backup configuration in OPNsense](img/opnsense-download-backup.png)

Clicking the `Download configuration` button, I downloaded the current `config.xml` in use my the instance, I though it was enough.

## Filesystem Corruption

I decided to recover the pkg database the worst possible way, I backed up the `/var/db/pkg` folder and I tried to `bootstrap` it.
```bash
cp -a /var/db/pkg /var/db/pkg.bak
pkg bootstrap -f
```
```
The package management tool is not yet installed on your system.
Do you want to fetch and install it now? [y/N]: y
Bootstrapping pkg from https://pkg.opnsense.org/FreeBSD:14:amd64/25.7/latest, please wait...
Verifying signature with trusted certificate pkg.opnsense.org.20250710... done
Installing pkg-1.19.2_5...
Extracting pkg-1.19.2_5:  13%
pkg-static: Fail to extract /usr/local/lib/libpkg.a from package: Write error
Extracting pkg-1.19.2_5: 100%

Failed to install the following 1 package(s): /tmp//pkg.pkg.scQnQs
Bootstrapping pkg from https://opn-repo.routerperformance.net/repo/FreeBSD:14:amd64, please wait...
pkg: Attempted to fetch https://opn-repo.routerperformance.net/repo/FreeBSD:14:amd64/Latest/pkg.pkg
pkg: Attempted to fetch https://opn-repo.routerperformance.net/repo/FreeBSD:14:amd64/Latest/pkg.txz
pkg: Error: Not Found
A pre-built version of pkg could not be found for your system.
```

I saw a `Write error`, I suspect a filesystem problem, I run a check on `fsck`, the output was a flood of inconsistencies:
```bash
fsck -n
```
```
[...]
INCORRECT BLOCK COUNT I=13221121 (208384 should be 208192)
INCORRECT BLOCK COUNT I=20112491 (8 should be 0)
INCORRECT BLOCK COUNT I=20352874 (570432 should be 569856)
[...]
FREE BLK COUNT(S) WRONG IN SUPERBLK
[...]
SUMMARY INFORMATION BAD
[...]
BLK(S) MISSING IN BIT MAPS
[...]
***** FILE SYSTEM IS LEFT MARKED AS DIRTY *****
```

The root filesystem was in bad shape.

Since I only had SSH at this point and no console access, I set up a forced `fsck` for next reboot:
```bash
sysrc fsck_y_enable="YES"
sysrc background_fsck="NO"
reboot
```

On the next boot, the filesystem was repaired enough to let me bootstrap `pkg` again, but most of the system packages were gone. My earlier upgrade while the disk was dirty had left me with a half-installed, half-missing software.

## When Things Got Worse

I discovered the utility `opnsense-bootstrap`, which promises to reinstall all packages and reset the system to a clean release, exactly what I was looking for:
- Remove all installed packages.
- Fresh 25.7 base system and kernel will be downloaded and installed.
- All standard OPNsense packages will be reinstalled.
```
opnsense-bootstrap
```
```
This utility will attempt to turn this installation into the latest OPNsense 25.7 release. All packages will be deleted, the base system and kernel will be replaced, and if all went well the system will automatically reboot. Proceed with this action? [y/N]:
```

I pressed `y`. This started well, but then... no more signal -> no more internet.

🙈 Oops.

After a while, I tried to reboot, but impossible to connect back via SSH. No other solution, I had to remove the router from the rack, put it on my desk and plug it a screen and a keyboard to see what is going on.

## Starting Over the Hard Way

This was bad:
```
Fatal error: Uncaught Error: Class "OPNsense\Core\Config" not found
in /usr/local/etc/inc/config.inc:143
```

Checking the bootstrap logs, this was even worse:
```
bad dir ino … mangled entry
Input/output error
```

The disk is in a bad shape, I can't do anything more for that instance, I'd better start from scratch now, I have backup, haven't it? (lol)

I downloaded the latest OPNsense ISO (v25.7) and put it into a USB stick. I reinstall OPNsense and overwrite the current installation, I kept everything as default.

## The Lifesaver: `config.xml`

OPNsense keeps the whole configuration in a single file: `/conf/config.xml`. That file was my lifeline.

I copied the `config.xml`file saved earlier into the USB stick. When plugged into the fresh OPNsense box, I overwrite the file with this one:
```bash
mount -t msdosfs /dev/da0s1 /mnt
cp /mnt/config.xml /conf/config.xml
```

I placed the router back in the rack, powered it on and crossed my fingers. beep!

The DHCP gave me an address, good start. I could reach its URL, awesome. My configuration is here, almost everything, but the plugins. I can't install them right away because they need another update, let's update it!

DNS is KO because the AdGuard Home plugin is not installed, I temporary set the system DNS to `1.1.1.1`

## The Last Breath

During that upgrade, the system threw errors again… and then rebooted itself. Another crash, not turning back on...

I can officially say that my NVMe drive is dead.

🪦 Rest in peace.

By chance, I have an unused NVMe Kingston drive of 512GB which was deliver with that box. I never used it because I preferred to use the one I was using before in my Vertex server.

I redo the same steps to reinstall OPNsense on that disk. I could finally update OPNsense to 25.7.1 and reinstall all the official plugins that I was using. 

To install custom plugins (AdGuard Home and Unifi), I had to add the custom repository `/usr/local/etc/pkg/repos/mimugmail.conf` (documentation [here](https://www.routerperformance.net/opnsense-repo/)) 
```json
mimugmail: {
  url: "https://opn-repo.routerperformance.net/repo/${ABI}",
  priority: 5,
  enabled: yes
}
```

After a final reboot, the router is almost ready, but I still don't have DNS services. This is because AdGuard Home is not configured.

⚠️ Custom plugin configuration is not saved within the standard backup in `config.xml`, which makes sense. As this is the only file I saved, I don't have any backup configuration for these plugins.

Reconfigure AdGuard Home is pretty straight forward, finally my DNS is working and everything is back to nominal, except the UniFi controller/

## Lessons Learned the Hard Way

OPNsense Backups

After a crash, healthcheck

- **Don’t reuse old hardware for critical services.** That NVMe was living on borrowed time.
    
- **Always trust but verify storage.** Run `smartctl`, run `fsck`, and don’t ignore write errors.
    
- **`config.xml` is the crown jewel.** With it, a full reinstall is almost painless. Without it, I would have been rebuilding from scratch.
    
- **Custom plugin configs are not in config.xml.** If you rely on AdGuard, UniFi, etc., back them up separately.
    
- **Know when to stop repairing.** I wasted hours trying to nurse a dead disk. Installing on new hardware fixed everything in minutes.


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