# GitOps Repository

This is my GitOps repository for my home cluster. Not included here are the
Ansible playbooks to setup and update all the nodes.

## Setup

Please have a look into the documentation 


## Hardware

I use a cluster of seven Raspberry PIs. Three for the controlplane and the other
four as worker nodes. After some time added two small Lenovo Thinkcentres inspired
by [TinyMiniMicro](https://www.servethehome.com/introducing-project-tinyminimicro-home-lab-revolution/).

You can find more details [here](https://mikevader.github.io/k3s-cluster-infra-apps/).


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
