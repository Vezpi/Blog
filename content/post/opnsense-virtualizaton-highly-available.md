---
slug: opnsense-virtualizaton-highly-available
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - proxmox
categories:
  - homelab
---
## Intro

I recently encountered my first real problem, my physical OPNsense box crashed because of a kernel panic, I've detailed what happened in that [post]({{< ref "post/10-opnsense-crash-disk-panic" >}}).

After this event, I came up with an idea to enhance the stability of the lab: **Virtualize OPNsense**.

The idea is pretty simple on paper, create an OPNsense VM on the **Proxmox** cluster and replace the current physical box by this VM. The challenge would be to have both the LAN and the WAN on the same physical link, involving true network segregation.

Having only one OPNsense VM would not solve my problem. I want to implement High Availability, the bare minimum would be to have 2 OPNsense instances, as active/passive.

---
## Current Setup

Currently, I have my ISB box, a *Freebox*, in bridge mode which is connected to the port `igc0` of my OPNsense box, the **WAN**. On `igc1`, my **LAN** is connected to my main switch on a trunk port with the VLAN1 as native, my management network.

Connected to that switch are my 3 Proxmox nodes, on trunk port as well with the same native VLAN. Each of my Proxmox nodes have 2 NICs, but the other is dedicated for the Ceph storage network, on a dedicated 2.5GB switch.

The layout changed a little since the OPNsense crash, I dropped the LACP link which was not giving any value:
![homelan-current-physical-layout.png](img/homelan-current-physical-layout.png)

---
## Target Layout

As I said in the intro, the plan is simple, replace the OPNsense box by a couple of VM in Proxmox. Basically, I will plug my ISB box directly to the main switch, but the native VLAN will have to change, I will create a VLAN dedicated for my WAN communication.

The real challenge will be located on the Proxmox networking, with only one NIC to support communication of LAN, WAN and even cluster, all of that on a 1Gbps port, I'm not sure of the outcome.

### Proxmox Networking

My Proxmox networking was quite dumb until really recently. Initially I only configured the network on each nodes. In that [article]({{< ref "post/11-proxmox-cluster-networking-sdn" >}}), I configured my VLANs in the Proxmox SDN.

Additionally, I have to add extra VLANs for this project, one for the WAN and the other for pfSync.

## Proof of Concept

Before rushing into a migration, I want to experiment the high availability setup for OPNsense. The idea would be to:
1. Add some VLANs in my Homelab
2. Create Fake ISP box
3. Build two OPNsense VMs
4. Configure high availability
5. Create another client VM
6. Shutdown the active OPNsense node
7. See what happen!

### Add VLANs in my Homelab

For this experiment, I add extra VLANs:
- 101: *POC WAN* 
- 102: *POC LAN*
- 103: *POC pfSync*

In the Proxmox UI, I navigate to `Datacenter` > `SDN` > `VNets` and I click `Create`:
![Create POC VLANs in the Proxmox SDN](img/proxmox-sdn-create-poc-vlans.png)

Once the 3 new VLAN have been created, I apply the configuration.

Additionally, I add these 3 VLANs in my UniFi controller, here only a name and the VLAN id are sufficient to broadcast the VLANs on the network. All declared VLANs are passing through the trunks where my Proxmox VE nodes are connected.

### Create Fake ISP Box VM

For this experience, I will simulate my current ISP box by a VM, `fake-freebox`, which will route the traffic between the *POC WAN* and the *POC LAN* networks. This VM will serve a DHCP server with only one lease, as my ISP box is doing. I clone my cloud-init template:
![proxmox-clone-template-fake-freebox.png](img/proxmox-clone-template-fake-freebox.png)

I add another NIC, then I edit the Netplan configuration to have:
- `eth0` (*POC WAN* VLAN 101): static IP address `10.101.0.254/24`
- enp6s19 (Lab VLAN 66): DHCP address given by my current OPNsense router
```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.101.0.254/24
    enp6s19:
      dhcp4: true
```

I enable packet forward to allow this VM to route traffic:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

I set up masquerading for this interface to avoid packet being dropped on my real network by the OPNsense router:
```bash
sudo iptables -t nat -A POSTROUTING -o enp6s19 -j MASQUERADE
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
```

I install `dnsmasq`, a small dhcp server:

```bash
sudo apt install dnsmasq -y
```

I edit the file `/etc/dnsmasq.conf` to configure `dnsmasq`  to serve only one lease `10.101.0.150` with DNS pointing to the OPNsense IP:
```
interface=eth0
bind-interfaces
dhcp-range=10.101.0.150,10.101.0.150,255.255.255.0,12h
dhcp-option=3,10.101.0.254      # default gateway = this VM
dhcp-option=6,192.168.66.1      # DNS server  
```

I restart the dnsmasq service to apply the configuration:
```bash
sudo systemctl restart dnsmasq
```

The `fake-freebox` VM is now ready to serve DHCP on VLAN 101 and serve only one lease.

### Build OPNsense VMs

First I download the OPNsense ISO from their website and I upload it to one of my Proxmox VE node storage:
![proxmox-upload-opnsense-iso.png](img/proxmox-upload-opnsense-iso.png)


I create the first VM from that node which I name `poc-opnsense-1`:
- I keep the OS type as Linux, even though OPNsense is based on FreeBSD
- I select `q35` machine type and `OVMH (UEFI)` BIOS setting, EFI storage on my Ceph pool
- For the disk, I set the disk size to 20GiB
- 2 vCPU with 2048 MB of RAM
- I select the VLAN 101 (*POC WAN*) for the NIC
- Once the VM creation wizard is finished, I add a second NIC in the VLAN 102 (*POC LAN*) and a third in the VLAN 103 (*POC pfSync*)
![proxmox-create-poc-vm-opnsense.png](img/proxmox-create-poc-vm-opnsense.png)


Before starting it, I clone this one to prepare the next one: `poc-opnsense-2`

Now I can start the VM, but the boot fails with an access denied. I enter the BIOS, navigate to Device Manager > Secure Boot Configuration, there I uncheck the `Attempt Secure Boot` option and restart the VM:
![proxmox-disable-secure-boot-option.png](img/proxmox-disable-secure-boot-option.png)

Now the VM boots on the ISO, I touch nothing until I get into that screen:
![opnsense-vm-installation-welcome.png](img/opnsense-vm-installation-welcome.png)

I enter the installation mode using the user `installer` and password `opnsense`. I select the French keyboard and select the `Install (UFS)` mode. I have a warning about RAM space but I proceed anyway.

I select the QEMU hard disk of 20GB as destination and launch the installation:
![opnsense-vm-installation-progress-bar.png](img/opnsense-vm-installation-progress-bar.png)

Once the installation is finished, I skip the root password change, I remove the ISO from the drive and select the reboot option at the end of the installation wizard.

When the VM has reboot, I log as `root` with the default password `opnsense` and land in the CLI menu:
![opnsense-vm-installation-cli-menu.png](img/opnsense-vm-installation-cli-menu.png)

I select the option 1 to assign interfaces, as the installer inverted them for my setup:
![opnsense-vm-installation-assign-interfaces.png](img/opnsense-vm-installation-assign-interfaces.png)

Now my WAN interface is getting the IP address 10.101.0.150/24 from my `fake-freebox` VM. Then I configure the LAN interface with `10.102.0.2/24` and configure a DHCP pool from `10.102.0.10` to `10.102.0.99`:
![opnsense-vm-installation-interfaces-configured.png](img/opnsense-vm-installation-interfaces-configured.png)

✅ The first VM is ready, I start over for the second OPNsense VM, `poc-opnsense-2` which will have the IP `10.102.0.3`

### Configure High Availability

Now both of the OPNsense VMs are operational, I want to configure the instances from their WebGUI. To be able to do that, I need to have access from the *POC LAN* VLAN to the OPNsense interfaces in that network. Simple way to do that, connect a WIndows VM in that VLAN and browse to the OPNsense IP address on port 443:
![opnsense-vm-webgui-from-poc-lan.png](img/opnsense-vm-webgui-from-poc-lan.png)

The first thing I do is to assign the third NIC, the `vtnet2` to the *pfSync* interface:
![opnsense-vm-assign-pfsync-interface.png](img/opnsense-vm-assign-pfsync-interface.png)

I enable the interface on each instance and configure it with a static IP address:
- **poc-opnsense-1**: `10.103.0.2/24`
- **poc-opnsense-2**: `10.103.0.3/24`

On both instances, I create a firewall rule to allow communication coming from this network on that *pfSync* interface:
![opnsense-vm-firewall-allow-pfsync.png](img/opnsense-vm-firewall-allow-pfsync.png)

Then I configure the HA in `System` > `High Availability` > `Settings`, on the master (`poc-opnsense-1`) I configure both the `General Settings` and the `Synchronization Settings`. On the backup (`poc-opnsense-2`) I only configure the `General Settings`:
![opnsense-vm-high-availability-settings.png](img/opnsense-vm-high-availability-settings.png)
