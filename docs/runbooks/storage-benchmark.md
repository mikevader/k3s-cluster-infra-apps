# Storage Benchmark Runbook

Compare the I/O performance of two storage classes on the same node with
[kbench](https://github.com/yasker/kbench) (a fio wrapper from the Longhorn authors).
Use it to answer questions like "how much slower is Longhorn than local disk on this worker?"
or "did the new disk / network / StorageClass setting actually help?".

## When to Use

- Before and after changing Longhorn settings (replica count, data locality, disk selector)
- After hardware changes (new NVMe, 10GbE storage network, see [Storage Network Runbook](storage-network-implementation.md))
- When [slow I/O](../troubleshooting/storage.md#slow-io) is suspected and you need numbers

## Manifests

Both manifests create two 31Gi PVCs and a one-shot `Job` that runs `cmp_run.sh`,
which benchmarks the first volume against the second.

| File | Volume 1 | Volume 2 | Node |
|------|----------|----------|------|
| [`kbench-localpath-vs-longhorn.yaml`](storage-benchmark/kbench-localpath-vs-longhorn.yaml) | `local-path` | `longhorn` | `k3sworker06` |
| [`kbench-localpath-vs-longhorn-test.yaml`](storage-benchmark/kbench-localpath-vs-longhorn-test.yaml) | `local-path` | `longhorn-test` | `k3sworker05` |

`longhorn-test` is defined in `cluster-critical-apps/longhorn-system/templates/storageclass-test.yaml`
(3 replicas, `diskSelector: ssd`, pinned to `k3sworker05`, `dataLocality: best-effort`). Edit it to
try different Longhorn parameters without touching the production `longhorn` class.

??? example "kbench-localpath-vs-longhorn.yaml"

    ```yaml
    --8<-- "docs/runbooks/storage-benchmark/kbench-localpath-vs-longhorn.yaml"
    ```

## Procedure

1. **Pick the node and storage classes.** Adjust `nodeSelector`, the PVC `storageClassName`s and the
   `FIRST_VOL_NAME` / `SECOND_VOL_NAME` labels. The node needs at least ~31Gi free for each volume.
   `SIZE` must be at or below the PVC size.

2. **Run it in a scratch namespace:**

    ```bash
    kubectl create namespace kbench
    kubectl -n kbench apply -f docs/runbooks/storage-benchmark/kbench-localpath-vs-longhorn.yaml
    ```

3. **Wait and read the results.** A full run takes a while (tens of minutes with 30G). Set
   `QUICK_MODE=1` in the Job env to check the setup first.

    ```bash
    kubectl -n kbench get pods -l kbench=fio -w
    kubectl -n kbench logs -l kbench=fio -f
    ```

    The final summary compares IOPS, bandwidth and latency (random/sequential, read/write) for both volumes.

4. **Record the results** next to earlier runs (see `docs/Performance.numbers`).

5. **Clean up.** The PVCs hold 2×31Gi, so delete them:

    ```bash
    kubectl delete namespace kbench
    ```

## Variations

- **Block mode:** switch both PVCs to `volumeMode: Block` and replace `volumeMounts` with the
  commented-out `volumeDevices` block. This removes filesystem overhead from the measurement.
- **CPU idle profiling:** set `CPU_IDLE_PROF=enabled` to also report CPU usage during the test.
- **Single volume:** kbench also supports `run.sh` with only `FILE_NAME` set. See the kbench README.
