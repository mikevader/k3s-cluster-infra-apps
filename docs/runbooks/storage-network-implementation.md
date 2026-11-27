# Storage Network Implementation Runbook

Based on [ADR: Dedicated Storage Network](../adr/storage-network.md)

**Date:** 2026-08-15

---

## Current State

- **Masters:** k3smaster1 (`.120`), k3smaster2 (`.121`), k3smaster4 (`.123`) — all on `192.168.42.0/24`, **single NIC only**
- **Workers:** k3sworker05-07 (`.134-.136`) — have dual NICs already (`ens18` internal, `ens19` external/VLAN 99)
- **k3s config:** `--node-ip` = `ansible_host` (192.168.42.x), no `--flannel-iface` set (defaults to primary)
- **Service templates:** `millriver.k3s` role uses systemd unit templates with inline flags
- **Service names:** masters = `k3s-server`, workers = `k3s-node`

## Target State (Two-NIC Layout from ADR)

| NIC                | Logical Traffic                  | k3s Flag                                |
|--------------------|----------------------------------|-----------------------------------------|
| **NIC1 (control)** | etcd + API + mgmt                | `--node-ip` (existing 192.168.42.x)     |
| **NIC2 (data)**    | pod overlay + Longhorn + TrueNAS | `--flannel-iface` (new 10GbE interface) |

> **Masters exception:** Masters have only one physical NIC. The data plane uses a
> VLAN sub-interface (`eth0.200`) on the same wire. This does **not** provide the
> physical bandwidth isolation the ADR recommends — it only provides logical separation
> and routing hygiene. True etcd isolation on masters requires adding a second NIC later.

---

## Phase 0: Hardware Prerequisites

- [x] **Workers + TrueNAS:** Verify each worker has a second NIC port (workers already have `ens19`)
- [x] If workers need 10GbE upgrade: purchase NICs (Intel X710 / Mellanox CX4-Lx)
- [x] Purchase managed 10GbE switch (MikroTik CRS309/326) if not already in place
- [x] Cable worker nodes and TrueNAS to the switch
- [x] Configure switch:
  - VLAN 200 (data) — trunked to master switch ports, untagged/access on worker data ports
  - MTU 9000 on all data VLAN ports
- [x] **Masters:** Configure existing switch ports as VLAN trunks carrying untagged mgmt + tagged VLAN 200

## Phase 1: OS-Level Network Configuration

### Workers (physical NIC2 = `ens19`)
- [x] Configure static IPs on `ens19` via netplan (subnet `10.20.2.0/24`)
- [ ] Set MTU 9000 on `ens19`

### Masters (VLAN sub-interface = `eth0.200`)
- [x] Install `vlan` package, load `8021q` kernel module
- [x] Create netplan config for `eth0.200` with VLAN ID 200, MTU 9000, static IP
- [x] Apply netplan

### All nodes
- [ ] Verify connectivity: `ping -M do -s 8972 <peer-on-data-subnet>` from every node
- [x] Verify MTU: `ip link show <data_iface>` shows `mtu 9000`

## Phase 2: Update Ansible Inventory (`hosts.yaml`)

Add new variables per node:

```yaml
kube_cluster:
  vars:
    data_vlan_id: 200
    data_interface: "eth0.200"    # VLAN sub-interface (default for masters)
  children:
    kube_master:
      hosts:
        k3smaster1:
          ansible_host: 192.168.42.120
          data_ip: 10.20.2.1
        k3smaster2:
          ansible_host: 192.168.42.121
          data_ip: 10.20.2.2
        k3smaster4:
          ansible_host: 192.168.42.123
          data_ip: 10.20.2.3
    kube_node:
      hosts:
        k3sworker05:
          ansible_host: 192.168.42.134
          data_ip: 10.20.2.11
          data_interface: ens19     # physical NIC2 (override group default)
        k3sworker06:
          ansible_host: 192.168.42.135
          data_ip: 10.20.2.12
          data_interface: ens19
        k3sworker07:
          ansible_host: 192.168.42.136
          data_ip: 10.20.2.13
          data_interface: ens19
```

## Phase 3: Update k3s Service Templates

**Server template** (`roles/millriver.k3s/templates/k3s-server.service.j2`) — add conditional `--flannel-iface`:

```diff
     --node-ip {{ ansible_host }} \
+{% if data_interface is defined %}
+    --flannel-iface {{ data_interface }} \
+{% endif %}
```

**Agent template** (`roles/millriver.k3s/templates/k3s-agent.service.j2`) — add conditional `--flannel-iface`:

```diff
     --protect-kernel-defaults=true \
+{% if data_interface is defined %}
+    --flannel-iface {{ data_interface }} \
+{% endif %}
     --node-ip {{ ansible_host }}
```

## Phase 4: Rolling Restart via `07_k3s_update` Pattern

Use the existing `serial: 1` rolling-update playbook logic (`08_storage_network.yml`):

1. **Pre-flight:** Validate data interface exists and is UP
2. **Cordon & drain** the node (`millriver.k3s-drain`)
3. **Deploy** updated service file (new `--flannel-iface` flag)
4. **Restart** k3s service (`systemctl restart k3s-server` on masters / `k3s-node` on workers)
5. **Verify** node comes back `Ready` and pods schedule
6. **Uncordon** (`millriver.k3s-uncordon`)
7. **Wait 30s** for cluster stabilization, then repeat for next node

> ⚠️ **Do masters first, one at a time.** etcd quorum requires 2/3 healthy. Never drain two masters simultaneously.

## Phase 5: Verify Network Separation

- [ ] Confirm flannel VXLAN traffic uses the data interface:
  ```bash
  tcpdump -i <data_iface> udp port 8472
  ```
- [ ] Confirm etcd traffic stays on control interface:
  ```bash
  ss -tnp | grep 2380   # should show 192.168.42.x addresses only
  ```
- [ ] Run pod-to-pod traffic test across nodes — verify it routes via data NIC
- [ ] Verify jumbo frames work end-to-end:
  ```bash
  ping -M do -s 8972 <peer-on-data-vlan>
  ```

## Phase 6: Longhorn Storage Network (Optional — Future Optimization)

> **Skipped for now.** With flannel pinned to the data VLAN, Longhorn replica traffic
> already rides the storage network (via the overlay). Multus is only needed to bypass
> flannel entirely for direct L2 replica traffic — an optimization for latency-sensitive
> workloads. Revisit if VXLAN overhead becomes measurable.

- [ ] Deploy **Multus CNI** to the cluster
- [ ] Create a `NetworkAttachmentDefinition` for the Longhorn VLAN on the data NIC
- [ ] Set Longhorn's `storage-network` setting to the NAD
- [ ] **Test on a throwaway volume first** — this detaches all volumes and requires Longhorn restart
- [ ] Verify Longhorn replica traffic uses the data interface directly (not via VXLAN)

## Phase 7: TrueNAS Integration

- [ ] Assign TrueNAS a data-subnet IP on its 10GbE port (e.g., `10.20.2.100`)
- [ ] Point NFS/iSCSI mounts at the TrueNAS data-subnet IP
- [ ] Configure iSCSI MPIO if dual-homed

---

## Rollback Plan

If a node doesn't come back healthy after the flannel-iface change:

1. SSH to the node via management IP (192.168.42.x — unaffected)
2. Remove `--flannel-iface` from the service file
3. Restart the service:
   - Masters: `systemctl restart k3s-server`
   - Workers: `systemctl restart k3s-node`
4. Uncordon the node

## Key Risks

| Risk                                                 | Mitigation                                                             |
|------------------------------------------------------|------------------------------------------------------------------------|
| MTU mismatch → silent packet drops                   | Verify jumbo frames end-to-end before k3s changes                      |
| Flannel can't bind to new interface                  | Test on one worker first (`--limit k3sworker05`) before rolling to all |
| etcd quorum loss during master restart               | `serial: 1` + verify quorum before proceeding                          |
| Longhorn volume detach during storage-network change | Use throwaway volume; schedule maintenance window                      |
| Masters share bandwidth (VLAN, not physical)         | Accept as limitation; plan NIC2 for masters later if needed            |
| Switch port not trunking VLAN 200                    | Verify switch config before running playbook                           |

## Firewall / Reachability Checklist

- Servers ↔ servers: `2379`, `2380` (etcd), `6443` (API) over **control** subnet (NIC1)
- All nodes → servers: `6443` (API) over control subnet
- Node ↔ node overlay: UDP `8472` (flannel VXLAN) over **data** subnet (NIC2)
- Longhorn replica: dynamically allocated ports (default range) over data subnet
- TrueNAS NFS: TCP `2049` + portmapper `111` over data subnet
- TrueNAS iSCSI: TCP `3260` over data subnet
