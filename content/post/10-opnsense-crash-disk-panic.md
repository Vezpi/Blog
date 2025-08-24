---
slug: opnsense-crash-disk-panic
title: My OPNsense Router Crash, from Panic to Reborn
description: The story of how I survived an OPNsense crash with a failing disk and why one backup XML made all the difference.
date: 2025-08-22
draft: true
tags:
  - opnsense
categories:
  - homelab
---
## Intro

This week, I experienced my first real problem on my homelab, which caused my whole home network to go down. 

My OPNsense router crashed and, after several failed recovery attempts, I finally had to reinstall it from scratch. Luckily, almost all of the configuration came back thanks to a single XML file. In that story, I will tell you what happened, what I did to recover and what I shouldn't have done.

This kind of exercise is the worst thing you want to happen because it's never funny to have everything go boom, but this is by far the best way to learn.

## The Calm Before the Storm

My OPNsense box had been running smoothly for months. Router, firewall, DNS, DHCP, VLANs, VPN, reverse proxy and even UniFi controller: all the pieces of my homelab run through it. but not only, it is also serving internet at home.

This box is the heart of my network, without it, I can hardly do anything. I have detailed how this is working in my [Homelab]({{< ref "page/homelab" >}}) section. It was “just working,” and I wasn’t worried about it. I felt confident, its backup was living only inside the machine...

Maybe too confident.

## The Unexpected Reboot

Out of nowhere, the box rebooted by itself just before midnight. By chance, I was just passing by my rack on my way to bed. I knew it had rebooted because I heard its little startup beep.

I wondered why the router restarted without my will. In my bed, I quickly checked if internet was working, and it was. But none of my services were available, my home automation or even this blog. I was tired, I would fix that the next day...

In the morning, looking at the logs, I found the culprit:
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

I thought I had dodged the bullet. I didn't investigate much on the root cause analysis: the kernel logs were polluted by one of the interfaces flapping, I thought it was just a bug. Instead, I went ahead and checked for updates, my first mistake.

My OPNsense instance was in version 25.1, and the newer 25.7 was available. Let's upgrade it, yay!

The upgrade rolled out successfully, but something was wrong. When I tried to look for any update, I saw a corruption in `pkg`, the package manager database:
```
pkg: sqlite error while executing iterator in file pkgdb_iterator.c:1110: database disk image is malformed
```

🚨 My internal alarm sensor triggered, I wondered about backups, I immediately decided to download the latest backup:
![Backup configuration in OPNsense](img/opnsense-download-backup.png)

Clicking the `Download configuration` button, I downloaded the current `config.xml` in use my the instance, I though it was enough.

## Filesystem Corruption

I decided to recover the pkg database the worst possible way, I backed up the `/var/db/pkg` folder and I tried to `bootstrap` it:
```bash
cp -a /var/db/pkg /var/db/pkg.bak
pkg bootstrap -f
```
```
The package management tool is not yet installed on your system.
Do you want to fetch and install it now? [y/N]: y
Bootstrapping pkg from https://pkg.opnsense.org/FreeBSD:14:amd64/25.7/latest, please wait...
[...]
pkg-static: Fail to extract /usr/local/lib/libpkg.a from package: Write error
Failed to install the following 1 package(s): /tmp//pkg.pkg.scQnQs
[...]
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

Wonderful!
```
opnsense-bootstrap
```
```
This utility will attempt to turn this installation into the latest OPNsense 25.7 release. All packages will be deleted, the base system and kernel will be replaced, and if all went well the system will automatically reboot. Proceed with this action? [y/N]:
```

I pressed `y`. This started well, but then... no more signal -> no more internet. I thought this bootstrap would save me. Instead, it buried me.

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

The disk is in a bad shape, at this point, I couldn’t save the install anymore. Time to start from scratch. Luckily, I had a backup… right?

I downloaded the latest OPNsense ISO (v25.7) and put it into a USB stick. I reinstall OPNsense and overwrite the current installation, I kept everything as default.

## The Lifesaver: `config.xml`

OPNsense keeps the whole configuration in a single file: `/conf/config.xml`. That file was my lifeline.

I copied the `config.xml`file saved earlier into the USB stick. When plugged into the fresh OPNsense box, I overwrite the file:
```bash
mount -t msdosfs /dev/da0s1 /mnt
cp /mnt/config.xml /conf/config.xml
```

I placed the router back in the rack, powered it on and crossed my fingers... *beep!* 🎉

The DHCP gave me an address, good start. I could reach its URL, awesome. My configuration is here, almost everything but the plugins, as expected. I can't install them right away because they need another update, let's update it!

This single XML file is the reason I could rebuild my router without losing my sanity

DNS is KO because the AdGuard Home plugin is not installed, I temporary set the system DNS to `1.1.1.1`

## The Last Breath

During that upgrade, the system threw errors again… and then rebooted itself. Another crash, not turning back on...

I can officially say that my NVMe drive is dead.

🪦 Rest in peace, thank you for your great services.

Luckily, I had a spare 512GB Kingston NVMe that came with that box. I never used it because I preferred to reuse the one inside my *Vertex* server.

I redo the same steps to reinstall OPNsense on that disk and this time everything worked: I could finally update OPNsense to 25.7.1 and reinstall all the official plugins that I was using. 

To install custom plugins (AdGuard Home and Unifi), I had to add the custom repository in `/usr/local/etc/pkg/repos/mimugmail.conf` (documentation [here](https://www.routerperformance.net/opnsense-repo/)) 
```json
mimugmail: {
  url: "https://opn-repo.routerperformance.net/repo/${ABI}",
  priority: 5,
  enabled: yes
}
```

After a final reboot, the router is almost ready, but I still don't have DNS services. This is because AdGuard Home is not configured.

⚠️ Custom plugin configuration is not saved within the backup in `config.xml`.

Reconfigure AdGuard Home is pretty straight forward, finally my DNS is working and everything is back to nominal... except the UniFi controller.

## Lessons Learned the Hard Way

- **Backups matter**: I always found myself thinking backups are not relevant... until you need to restore and it's too late.
- **Keep backups off the box**: I was lucky to get the `config.xml` before my disk die, I would have a really hard time to fully recover.
- **Healthcheck after a crash**: Do not ignore a kernel panic.
- **I/O errors = red flag**: I should have stopped trying to repair. I lost hours fighting a dead disk.
- **Custom plugin configs aren’t include**d: OPNsense configuration and its official plugin are saved into the backups, this is not the case for the others.
- **My router is a SPOF** (*single point of failure*): In my homelab, I wanted to have most of my elements highly available, I need to find a better solution.

## Moving Forward

I really need to think on my backup strategy. I'm too lazy and always keep it for later, until it is too late. It's been a long time since I've been struck by a hardware failure. When it strikes, it hurts.

Initially I wanted my router to be in its own hardware because I thought it was safe, I was damn wrong. I will think on a solution to virtualize OPNsense in Proxmox to have it highly available, a great project in perspective!

## Conclusion

My OPNsense router went from a random reboot to a dead disk, with a rollercoaster of troubleshooting. In the end, I'm almost happy with what happened, it taught me more than any smooth upgrade ever could.

If you run OPNsense (or any router), remember this:  
**Keep a backup off the box.**

Because when things go wrong, and eventually they will, that one little XML file can save your homelab.

Stay safe, make backups.