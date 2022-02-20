# Raspberry Pi GitOps Stack

This document describes my current setup of my Rasperry Pi k8s cluster. Although everything should be reflected in code, usually my brain discards stuff which works ... now. The not-working is a problem for future brain 😄

So the text is mainly meant for me to keep track of how and why I did certain things. If somebody else finds value in it: great!

Although the whole thing is a private project for educational purposes, I try to keep it as production ready as possible. Often the biggest learnings stem from corner cases. 
That means, at least for me, to stay true to the following points:

* Everything is automated, no manual kubectl commands
* Clear separation between public and private network
* Use secure connections
    * All HTTPS connections have correct certificates from LetcEncrypt
* Disaster recovery is easy to do
* Critical parts of the system (like control-plane, networking, etc) are setup in HA


## Vault Secret Injection with CSI

One way to use credentials from the vault inside pods is with CSI.

* Use Vault with CSI
* Install CSI Driver CRD with Chart



--8<-- "includes/abbreviations.md"
