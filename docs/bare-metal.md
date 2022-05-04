# Harware Setup of Raspberry PIs

The initial setup is done with Ansible.


## (Optional) Rolling Update

The initial ansible script is not very suitable for rolling updates as it
assumes it is about to initialize a cluster which requires the order

1. First master node which initializes (or restores) the etcd state
2. All other master nodes which sync up to the first
3. All worker nodes

That is very efficient for setup and restore but would mean some outages if
applied on a live cluster. Therefore we need a playbook which goes through
every node sequentially (we have no special requirement on performance) and
cares about draining nodes correctly.

Ideally we can reuse roles from the cluster setup playbook.
