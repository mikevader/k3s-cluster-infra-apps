# Setup Proxmox

Proxmox is an OpenSource virtualization software. The largere nodes are setup
with it and the nodes on it virtualized.


## Install Proxmox

First create a boot USB stick with Proxmox VE Installer ISO.

Select ZFS as filesystem as it will set the bootloader to systemd-boot instead of GRUB.


## First steps on a new Proxmox server

After setting up a new Proxmox server, there are a few things to do before they
can be used. Idealy those steps would be automated but ...

Those steps are heavily inspired by [techno tim setup article][tt-proxmox]


### Updates

Edit `/etc/apt/sources.list`

```shell
deb http://ftp.debian.org/debian bullseye main contrib

deb http://ftp.debian.org/debian bullseye-updates main contrib

# security updates
deb http://security.debian.org/debian-security bullseye-security main contrib

# PVE pve-no-subscription repository provided by proxmox.com,
# NOT recommended for production use
deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription
```

Edit `/etc/apt/sources.list.d/pve-enterprise.list`

```shell
# deb https://enterprise.proxmox.com/debian/pve buster pve-enterprise
```

Run

```bash
apt-get update

apt full-upgrade

reboot
```

### Storage

BE CAREFUL. This is meant for the storage/longhorn disks as it will wipe it

```shell caption="select the correct disk device"
fdisk /dev/sda
```

Then P for partition, then D for delete and W for write.

### IOMMU  (PCI Passthrough)

See [Proxmox PCI Passthrough](https://pve.proxmox.com/wiki/Pci_passthrough)

First make sure IOMMU is enabled in the BIOS.

`nano /etc/kernel/cmdline`

Add `intel_iommu=on iommu=pt` to the end of this line without line breaks. (for
AMD processors add `amd_iommu=on ...`)

```shell
root=ZFS=rpool/ROOT/pve-1 boot=zfs intel_iommu=on iommu=pt
```

Edit `/etc/modules` and add

```shell
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

run

```shell
update-initramfs -u -k all
# or proxmox-boot-tool refresh

reboot
```

### VLAN Aware

Setup the network interface to handle VLANs.

```bash
nano /etc/network/interfaces
```

Add the following lines to the main network interface

```shell
bridge-vlan-aware yes
bridge-vids 2-4094
```


### ISOs

Define images:

* https://releases.ubuntu.com/22.10/ubuntu-22.10-live-server-amd64.iso


## Setup worker node

Depending on the usage the parameters may vary. But following is a node which is
part of the longhorn storage and has an interface to the internet.

* General:
  * Node: pve1-x
  * Name: k3sworker
  * Start at boot: true
* OS:
  * ISO Image: ubuntu server installer
* System:
  * Qemu Agent: true
* Disks:
  * disk 1:
    * Storage: virtual
    * Size: 64 GB
    * Backup: yes
    * Skip replication: no
    * Discard: yes
    * SSD emulation: yes
  * disk 2:
    * Storage: virtual
    * Size: >512 GB
    * Backup: no
    * Skip replication: yes
    * Discard: yes
    * SSD emulation: yes
* CPU:
  * Sockets: 1
  * Cores: 2-12
* Memory:
  * min 32 GB
  * max 64 GB
* Network:
  * net0
    * Bridge: vmbr0
  * net1
    * Bridge: vmbr0
    * vlan tag: 99

Don't forget to define the generated mac address in DHCP


### Install Qemu Agent

```bash
ssh devops@k3sworker<xy>
sudo apt-get install qemu-guest-agent
```



## References

[tt-proxmox]: https://docs.technotim.live/posts/first-11-things-proxmox/



--8<-- "includes/abbreviations.md"
