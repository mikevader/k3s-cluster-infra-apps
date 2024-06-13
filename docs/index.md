# Raspberry Pi GitOps Stack

This document describes my current setup of my Rasperry Pi k8s cluster. Although everything should be reflected in code,
usually my brain discards stuff which works ... now. The not-working is a problem for future brain 😄

So the text is mainly meant for me to keep track of how and why I did certain things. If somebody else finds value in
it: great!

Although the whole thing is a private project for educational purposes, I try to keep it as production ready as
possible. Often the biggest learnings stem from corner cases. 
That means, at least for me, to stay true to the following points:

* Everything is automated, no manual kubectl commands
* Clear separation between public and private network
* Use secure connections
    * All HTTPS connections have correct certificates from LetcEncrypt
* Disaster recovery is easy to do
* Critical parts of the system (like control-plane, networking, etc) are setup in HA


## Hardware

I use the following hardware setup for this:

* 3 Raspberry PI 4s with 8GB Ram and Corsair GTX USB Stick as Disk
* 4 Raspberry PI 4s with 8GB Ram, Corsair GTX USB Stick as Boot Disk and an
  external USB/NVME Drive (which has to be powered separatly)
* Lenovo Thinkcentre M720q with 64GB Ram with Proxmox and large HDD
* Lenovo Thinkcentre M75q with 64GB Ram with Proxmox and large HDD

The first are used for the control plane, the other fours are used as worker
nodes. Some of them are powered with PoE hats. The faster external drives are
used for longhorn.

## GitOps

Inspired from
* https://github.com/onedr0p/home-ops
* https://github.com/bjw-s/home-ops
* https://github.com/dirtycajunrice/gitops
* [TinyMiniMicro](https://www.servethehome.com/introducing-project-tinyminimicro-home-lab-revolution/)
* 

--8<-- "includes/abbreviations.md"
