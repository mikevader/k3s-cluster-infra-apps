# GitOps Repository

This is my GitOps repository for my home cluster. Not included here are the
Ansible playbooks to setup and update all the nodes.

## Setup

Please have a look into the documentation 


## Hardware

I use a cluster of seven Raspberry PIs. Three for the controlplane and the other
four as worker nodes. Each of the worker nodes has a 2 TB SSD used for longhorn.

I created the case myself with simple arylglass :)

Sources for good HW Ideas is of course the [TinyMiniMicro](https://www.servethehome.com/introducing-project-tinyminimicro-home-lab-revolution/)
project from ServeTheHome. Or one of the many stores for older server center
hardware like:


I explicitly decided against using server center hardware because I wanted to
have multiple actual nodes which have diffirent downtimes and outages. If I
wouldn't use the cluster as homelab the obvious solution would be a few servers
with virtualisation.


Order on initialization:

1. cluster itself
2. argocd
3. applicationset
3. applicationset init
    1. reference to self
4. application set platform
    1. metallb
        * Add secret for memberlist
    2. cert-manager
        * Add token for digital ocean
    3. traefik
    4. longhorn
        * longhorn disks mounted
    5. 


# copy volume to volume with rsync

rsync -azP source/ destination

-a: archive
include -r (recursive for folders)
and preserves symbolic links, special and device files, modification times, groups, owners and permissions

-z: compression
Useful if used over the network

-P: progress & partial

-nv: dryrun and verbose

trailing slash (`/`) on source is important otherwise itself will be moved as well


## Benchmarks


### Storage

kbench with compare to local-path: https://github.com/yasker/kbench#deploy-comparison-benchmark-in-kubernetes-cluster


### Network

Install iperf with `sudo apt-get install iperf`

Initialize server with `iperf -s` -> listens on port 5001

Start test on client with `iperf -c <server-ip>`


Options:

`-p` to change default port

Reference: https://www.baeldung.com/linux/iperf-measure-network-performance

Tools zu installieren: 
- git clone https://github.com/yasker/kbench.git
- iperf
- fio
- jq
