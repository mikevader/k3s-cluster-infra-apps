# Council Verdict: Dedicated Storage Network for k3s + Longhorn + TrueNAS

**Question:** For a k3s cluster (3 masters + 3 workers) with Longhorn distributed storage
plus a separate TrueNAS server for very large volumes, is a physically dedicated network
connection for storage/data traffic a good idea, and what is the best overall network setup?

**Date:** 2026-07-13

---

## Where the Council Agrees

- **Yes, dedicate the storage network — but physical separation, not just a VLAN.**
  A VLAN riding the *same NIC and uplink* is "theater": VLANs partition broadcast domains,
  not bandwidth. Real isolation needs a **separate physical NIC port** per node.
- **1GbE is a non-starter for replicated Longhorn.** 10GbE is the floor (Longhorn's own
  docs). Three-way synchronous replication means every write crosses the wire 2× more before
  it ACKs; on 1GbE you saturate ~110 MB/s, the 8-second replica timeout fires, rebuilds eat
  more bandwidth, and you spiral into node-flapping.
- **Jumbo frames (MTU 9000) end-to-end — or not at all.** One device left at 1500 causes
  silent fragmentation / black-holed packets that look exactly like "random Longhorn
  timeouts." Verify with `ping -M do -s 8972 <peer>`.
- **Longhorn and TrueNAS iSCSI/NFS should not share one flat storage segment.** iSCSI wants
  MPIO, NFS wants a stable mount, Longhorn wants low jitter — separate VLANs at minimum.

## Where the Council Clashes

- **10GbE vs 25GbE.** The Executor and Contrarian say **dual-10GbE is right-sized** for
  homelab (used Intel X710 / Mellanox CX4-Lx ~$40–70, one MikroTik CRS309/326 ~$300). The
  Expansionist says **skip straight to dual-25G SFP28** (RoCEv2-capable) as a future GPU/SAN
  fabric — "cable once for a decade." **All three peer reviewers sided against the
  Expansionist**, calling 25G/RoCE/SPDK premature for homelab workloads. RoCEv2 also needs
  PFC/DCB switch config — not homelab-trivial.
- **Is the whole topology even justified?** The Outsider argued 3 masters for a solo operator
  is "HA theater" and running Longhorn *and* TrueNAS is two answers to one question. A real
  cost/complexity tension, independent of the network decision.

## Blind Spots the Council Caught

- **The etcd starvation loop is the deepest insight (all 3 reviewers ranked it strongest).**
  The real reason to separate isn't bandwidth, it's *failure semantics*. etcd Raft heartbeats
  are latency-critical. A Longhorn rebuild storm saturates a shared link → etcd heartbeats
  starve → nodes go `NotReady` → Longhorn declares replicas stale → rebuilds *harder*. That
  feedback loop **is** the flapping. Isolate etcd **first** — it is the cheapest and
  highest-consequence protection.
- **The storage network becomes a new single point of failure.** A lone dedicated storage
  NIC/switch, if it dies, detaches *every* Longhorn volume cluster-wide and hangs all pods.
  Use **bonded/dual links (LACP or MPIO)**, not a single cable.
- **Longhorn traffic is bursty, not sustained.** 10GbE matters for the *rebuild window* and
  latency, not steady saturation — reinforcing "10G is plenty, 25G is wasted."
- **No monitoring plan.** Alert on link saturation and replica degradation to catch trouble
  *before* it flaps.

---

## Traffic Classes — Expanded

Think in terms of **four traffic classes**, ordered by how cheaply and how critically they
must be isolated. The core principle: **latency-critical traffic must never share a link with
bandwidth-hungry traffic that can saturate it.** etcd (tiny, latency-murderous) and Longhorn
rebuilds (bursty, bandwidth-hungry) are the dangerous pairing.

### 1. Control-plane / etcd — protect first, costs almost nothing

- **What it is:** kube-apiserver ↔ node communication, and — because k3s uses **embedded
  etcd** in an HA setup — the etcd peer (port `2380`) and client (port `2379`) Raft traffic
  between the 3 servers.
- **Profile:** Tiny bandwidth (kilobytes), but *murderous* latency and jitter sensitivity.
  etcd's Raft election and heartbeat timeouts are in the low hundreds of milliseconds. A few
  hundred ms of added latency from a saturated link triggers leader elections → the cluster
  goes unstable even though nothing is "down."
- **Isolation goal:** Keep this off any link that Longhorn rebuilds can saturate. This is the
  single highest-ROI isolation you can do.

### 2. Longhorn replication — its own L2, MTU 9000

- **What it is:** Synchronous replica traffic between Longhorn engine and its replicas on
  other nodes. Every volume write is mirrored to 2–3 replicas before ACK.
- **Profile:** High bandwidth **and** latency-sensitive. Bursty — rebuilds after a node
  reboot or disk failure will saturate the link for minutes.
- **Isolation goal:** Dedicated storage NIC port, own VLAN, jumbo frames. Bind Longhorn to it
  explicitly (see Multus note in the build plan).

### 3. TrueNAS NFS / iSCSI — own VLAN, MPIO for iSCSI

- **What it is:** Large-volume access from pods to the TrueNAS box.
- **Profile:** High bandwidth, but **latency-tolerant** relative to Longhorn/etcd. iSCSI
  benefits from MPIO (multipath) for both throughput and failover; NFS wants a stable mount.
- **Isolation goal:** Separate VLAN from Longhorn replication so the two storage systems don't
  fight over the same queue. Point mounts at the TrueNAS storage-subnet IP explicitly.

### 4. Pod / application (flannel overlay) + management — the "everything else" plane

- **What it is:** Pod-to-pod overlay traffic (flannel VXLAN/WireGuard) and general
  management/ingress.
- **Profile:** Variable, mostly latency-tolerant. This is what you're protecting the other
  three classes *from*.

### Should the etcd / control-plane class include all nodes?

**Not identically — the distinction is servers vs agents.**

- **The 3 server (master) nodes carry embedded etcd.** They *must* reach each other over
  their private/isolated IPs on ports `2379` and `2380`. This is the traffic that most needs
  protecting, and it exists **only between the 3 servers**.
- **The 3 worker (agent) nodes do not run etcd.** But they still have control-plane traffic:
  the kubelet talks to kube-apiserver on `6443`. So all 6 nodes participate in the
  "control-plane" class, but only the 3 servers carry the latency-critical etcd Raft
  component.

**Practical takeaway:** put **all 6 nodes'** `--node-ip` (control-plane traffic) on the
isolated/private interface. The etcd peer traffic then naturally rides that interface on the
3 servers, and agent→apiserver traffic rides it on the workers. You do **not** need a special
per-role network config beyond ensuring every node's private interface can reach the servers
on `6443`, and the servers can reach each other on `2379`/`2380`.

---

## Physical NIC Mapping (Two-NIC Build)

The four classes are four *logical* networks (separate subnets/VLANs). With **two physical
ports per node**, the design question is how to pack four logical networks onto two wires.
The rule that governs everything: **the dangerous pairing is etcd + Longhorn on the same
wire** (latency-critical victim + bandwidth-hungry cause). Any layout that keeps those two
apart is correct — but one layout is best.

### Recommended two-NIC layout

| Physical port | Logical classes (VLANs) | k3s flag |
|---|---|---|
| **NIC1 — control** | etcd/control-plane + mgmt | `--node-ip` on this subnet |
| **NIC2 — data** | pod overlay + Longhorn replication + TrueNAS NFS/iSCSI | `--flannel-iface` = this interface |

**Why this is the strongest two-NIC layout:** NIC1 carries only etcd + mgmt — both tiny and
predictable — so etcd gets a wire essentially to itself. That is the safest home for the one
class whose failure mode (Raft election storms → `NotReady` → flapping) is the entire reason
for separating traffic. The three bandwidth consumers (pod overlay, Longhorn, TrueNAS) share
NIC2, but they all tolerate contention far better than etcd: pod overlay and TrueNAS are
latency-tolerant, and Longhorn degrades *gracefully* (slower I/O) when it's the victim of
contention rather than the cause of etcd starvation.

**Why not "storage on one NIC, everything else on the other":** that also keeps etcd off the
Longhorn wire, so it's acceptable — but it mixes etcd (most latency-critical) with pod overlay
(least predictable) on NIC1. A container image pull or a chatty app can spike pod traffic and
add latency to etcd. Putting etcd nearly alone on NIC1 is the safer prioritization.

**The tradeoff you're accepting:** a Longhorn rebuild storm can now slow both TrueNAS I/O and
pod-overlay traffic on NIC2. In a homelab this is almost always fine — rebuilds are occasional
and bursty. If it ever becomes a real problem, that's your signal to add a third NIC and split
Longhorn onto its own wire.

> **VLANs don't isolate bandwidth — physical ports do.** The three VLANs on NIC2 still share
> that NIC's 10 Gbps. Separating them into VLANs buys you addressing/routing hygiene and
> per-class firewalling, not contention protection. Only a third physical port removes the
> Longhorn-vs-TrueNAS contention on NIC2.

> **Bonding vs splitting.** You could instead LACP-bond both ports into one ~20 Gbps pipe
> carrying all four VLANs — gaining redundancy and burst throughput but losing the hard
> physical guarantee that a Longhorn rebuild can't starve etcd. With only two ports you can
> have hard etcd isolation **or** full-bandwidth redundancy, not both. The council leaned
> toward physical split to keep the etcd guarantee.

---

## Setting This Up in k3s

k3s splits traffic across interfaces using two independent flags — this is the mechanism that
lets you separate control-plane from pod-overlay traffic:

- **`--node-ip`** sets the node's internal IP. This governs the **control-plane** plane:
  kube-apiserver ↔ node communication and (on servers) the embedded-etcd peer/client traffic
  on `2379`/`2380`. Point this at your isolated private interface.
- **`--flannel-iface`** sets the interface flannel uses for the **pod overlay (data-plane)**.
  Set it explicitly — if omitted, flannel falls back to the default-route interface, which
  may push overlay traffic onto the wrong (e.g. public) NIC.
- **`--node-external-ip`** (optional) is the public/ingress IP, kept separate from the two
  above.

> **Important nuance (from the k3s maintainers' discussion):** With `--node-ip` set to a
> private IP *and* `--flannel-iface` explicitly set, flannel correctly uses the private IP.
> But if you set `--node-external-ip` and *omit* `--flannel-iface`, flannel picks the
> default-route (often public) interface instead. **Always set `--flannel-iface` explicitly**
> to keep the data-plane pinned to your chosen interface.

### Example config

Mapping the two-NIC layout to interfaces:

- **`eth1` = NIC1 (control)**, subnet `10.20.1.0/24` — carries etcd/control-plane + mgmt.
  `--node-ip` lives here.
- **`eth2` = NIC2 (data)**, subnet `10.20.2.0/24` — carries pod overlay + Longhorn + TrueNAS.
  `--flannel-iface` points here so the pod overlay rides the data wire, **not** the control
  wire.

This is the whole reason k3s has two separate flags: `--node-ip` and `--flannel-iface` can sit
on **different physical NICs**, which is exactly what splits control-plane from pod-overlay
across your two wires.

**First server (cluster-init), `/etc/rancher/k3s/config.yaml`:**

```yaml
# server #1 — control 10.20.1.1 / data 10.20.2.1
cluster-init: true
node-ip: "10.20.1.1"          # control-plane + embedded etcd (2379/2380) ride NIC1 (eth1)
flannel-iface: "eth2"          # pod overlay rides NIC2 (data wire), keeping etcd's NIC clear
# node-external-ip: "..."      # optional: public/ingress IP, if needed
tls-san:
  - "10.20.1.1"                # add a VIP/LB name here if you front the API with one
```

**Additional servers (join), `/etc/rancher/k3s/config.yaml`:**

```yaml
# server #2 — control 10.20.1.2 / data 10.20.2.2 (server #3 analogous: .3)
server: "https://10.20.1.1:6443"
token: "<node-token from server #1>"
node-ip: "10.20.1.2"           # control NIC
flannel-iface: "eth2"          # data NIC
```

**Agent / worker nodes (join), `/etc/rancher/k3s/config.yaml`:**

```yaml
# worker — control 10.20.1.11 / data 10.20.2.11  (.11 .. .13)
server: "https://10.20.1.1:6443"   # or the API VIP, if you have one
token: "<node-token>"
node-ip: "10.20.1.11"              # kubelet ↔ apiserver over NIC1 (control)
flannel-iface: "eth2"              # pod overlay over NIC2 (data)
```

> **Note on the API server address:** with 3 embedded-etcd servers you'll normally front the
> API with a virtual IP (e.g. kube-vip) or an external LB so nodes don't hard-depend on
> server #1. Put that VIP in every server's `tls-san` and use it as the `server:` value on the
> other servers and all agents.

### Where does Longhorn / NFS / iSCSI fit?

The k3s flags above cover **control-plane + pod overlay**. The *storage-data* classes are a
separate concern layered on top:

- **Longhorn replication:** deploy **Multus**, create a `NetworkAttachmentDefinition` on the
  **data interface (NIC2 / `eth2`)** — its own VLAN on that wire in the two-NIC build, or a
  dedicated third interface if you later add one — then set Longhorn's global
  **`storage-network`** setting to that NAD. This requires a Longhorn restart and detaches
  volumes — **test on a throwaway volume first.**
- **TrueNAS NFS/iSCSI:** point mounts / iSCSI portals at the TrueNAS data-subnet IP
  explicitly, on its own VLAN on NIC2. Enable iSCSI MPIO if TrueNAS and nodes are dual-homed.

### Firewall / reachability checklist

- Servers ↔ servers: `2379`, `2380` (etcd), `6443` (API) over the **control** subnet (NIC1).
- All nodes → servers: `6443` (API) over the control subnet.
- Node ↔ node overlay: UDP `8472` (flannel VXLAN) **or** UDP `51820`/`51821` (flannel
  WireGuard, if you want the overlay encrypted) — over the **data** subnet (NIC2), since
  `--flannel-iface` points there.
- Verify jumbo frames actually work before trusting them, on the data wire:
  `ping -M do -s 8972 <peer-on-data-vlan>`.

---

## The Recommendation

Build a dedicated storage network on **separate physical NICs, sized at 10GbE**, with the
four traffic classes above logically separated — and **protect etcd above all**.

1. **NICs:** Dual-port 10GbE per node (Intel X710 or Mellanox ConnectX-4 Lx, used ~$40–70).
   TrueNAS gets dual-port 10GbE too.
2. **Two-NIC mapping:** **NIC1 = etcd/control-plane + mgmt** (nearly private, gives etcd its
   own wire); **NIC2 = pod overlay + Longhorn + TrueNAS**. This is the strongest two-NIC
   layout — it moves contention onto the classes that absorb it and keeps the latency-critical
   class clear. Add a third NIC later only if a Longhorn rebuild slowing NIC2 becomes a real
   problem.
3. **Switch:** One managed 10GbE switch (MikroTik CRS309/326 ~$300), VLAN'd. A second switch
   is overkill *unless* you want to eliminate the switch SPOF.
4. **k3s:** `--node-ip` on the NIC1 (control) subnet and `--flannel-iface` on NIC2 (data) for
   all 6 nodes (see config above) — the two flags on two different NICs are what split
   control-plane from pod-overlay.
5. **Longhorn:** Multus `NetworkAttachmentDefinition` on the NIC2 data VLAN + `storage-network`
   setting; test on a throwaway volume.
6. **Don't over-buy.** Skip 25G/RoCE unless you have a *named* future workload (GPU training,
   Ceph) that needs it.

**Redundancy caveat:** with only two ports you can have hard etcd isolation (physical split,
recommended) **or** LACP-bonded full-bandwidth redundancy, not both. If you value the etcd
guarantee — and given that flapping is the failure you're preventing, you should — take the
split. Revisit bonding only if you add more ports.

Take the Outsider's challenge seriously: for a solo homelab, weigh whether you need 3 masters
(vs 1 master + regular etcd snapshots to TrueNAS) and whether both Longhorn and TrueNAS earn
their double ops burden. These are cost/complexity calls independent of the network.

## The One Thing to Do First

**Before buying anything, verify the physical constraints:** does every node have a free PCIe
slot for a second NIC, and does your budget cover a managed 10GbE switch with enough ports? If
the honest answer is "I can only do 1GbE with VLANs," then **don't run Longhorn with
multi-replica synchronous replication at all** — you'd be building a cluster that flaps. That
single hardware check determines whether the whole plan is viable.

---

## Sources

- [K3s — Basic Network Options](https://docs.k3s.io/networking/basic-network-options)
- [K3s — Network Options](https://docs.k3s.io/installation/network-options)
- [K3s — Networking](https://docs.k3s.io/networking)
- [K3s — Requirements (ports)](https://docs.k3s.io/installation/requirements)
- [GitHub Discussion #9888 — `--node-ip` vs `--node-public-ip` vs `--flannel-iface`](https://github.com/k3s-io/k3s/discussions/9888)
- [Production-ready K3s with OpenFaaS (two-interface example)](https://www.openfaas.com/blog/production-faas-linode/)
