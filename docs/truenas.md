---
title: TrueNAS
description: TrueNAS is an open-source storage operating system that provides a powerful and flexible platform for managing data storage.
---

## Initial Pool

I created a ZFS pool named `bigone` with the following command


## K8s Volumes

The idea is to use TrueNAS as a storage backend for Kubernetes, allowing you to create persistent volumes that can be
used by your applications. You need to define both a storage class which can connect to TrueNAS and obviously a dataset.

Resources

* https://github.com/fenio/k8s-truenas?tab=readme-ov-file (main)
* https://www.truenas.com/blog/truenas-enables-container-storage-and-kubernetes/
* https://www.truenas.com/docs/solutions/integrations/containers/
* https://jonathangazeley.com/2021/01/05/using-truenas-to-provide-persistent-storage-for-kubernetes/

### Dataset

To create a dataset for Kubernetes, you can use the TrueNAS web interface or the CLI. The dataset should be created under the ZFS pool you created earlier.
You can create a dataset named `k8s` under the `bigone` pool in the web interface like this:

Under this dataset, you can create sub-datasets for NFS, iSCSI, etc. For example, you can create a sub-dataset named `nfs` for NFS volumes.







### Storage Class

You need a driver as well. We are going to use democratic CSI driver, which is available in the [democratic-csi](https://artifacthub.io/packages/helm/democratic-csi/democratic-csi)

```yaml title="values.yaml"
---
democratic-csi:
  controller:
    driver:
      image:
        tag: next
  csiDriver:
    name: "nfs"
  storageClasses:
    - name: truenas-nfs # (4)!
      defaultClass: false
      reclaimPolicy: Delete
      volumeBindingMode: Immediate
      allowVolumeExpansion: true
      parameters:
        fsType: nfs
        detachedVolumesFromSnapshots: "false"
      mountOptions:
        - noatime
        - nfsvers=3
      secrets:
        provisioner-secret:
        controller-publish-secret:
        node-stage-secret:
        node-publish-secret:
        controller-expand-secret:
  volumeSnapshotClasses:
    - name: nfs
      parameters:
        detachedSnapshots: "true"
  driver:
    config:
      driver: freenas-api-nfs
      instance_id:
      httpConnection:
        apiVersion: 2
        protocol: http
        host: 192.168.1.210 # (3)!
        port: 80
        apiKey: someApiKey # (1)!
        allowInsecure: true
      zfs:
        datasetParentName: bigone/k8s/nfs/v # (2)!
        detachedSnapshotsDatasetParentName: bigone/k8s/nfs/s # (2)!
        datasetEnableQuotas: true
        datasetEnableReservation: false
        datasetPermissionsMode: "0777"
        datasetPermissionsUser: 0
        datasetPermissionsGroup: 0
      nfs:
        shareHost: 192.168.42.210 # (3)!
        shareAlldirs: false
        shareAllowedHosts: [ ]
        shareAllowedNetworks: [ ]
        shareMaprootUser: root
        shareMaprootGroup: root
        shareMapallUser: ""
        shareMapallGroup: ""

1. Replace with your API key from TrueNAS. You can find it in the TrueNAS web interface under `System` -> `API Keys`.
   Make sure to create a new API key with the necessary permissions for the CSI driver to access the NFS shares.
2. Replace with the desired parent dataset name for your NFS volumes. This is where the CSI driver will create datasets for each persistent volume.
3. Replace with the IP address of your TrueNAS server. This is the address where the NFS shares will be accessible from your Kubernetes cluster.
4. This is the name of the storage class that will be used to provision NFS volumes in Kubernetes. You can change it to whatever you prefer.
```

## Time Machine Backup

Create a dataset for Time Machine backups, e.g. `bigone/timemachine`.

Then create a NFS share for this dataset in the TrueNAS web interface:

1. Go to `Sharing` -> `Unix Shares (NFS)`.
2. Click on `Add`.
3. Set the `Path` to the dataset you created for Time Machine backups, e.g. `/mnt/bigone/timemachine`.
4. Set the `Purpose` to Multi-user time machine backups.
5. Under `Access`
   * Enable Browsable to Network Clients.
6. Under `Other Options`
   * Enable `Time Machine`.
   * Enable `Enable Shadow Copies`
   * Enable `Enable Alternate Data Streams`
   * Enable `Enable SMB2/3 Durable Handles`


## Minio

* Add Dataset: `bigone/minio`
* Install Minio App





## Performance Testing


Got the following idea from the Proxmox forum [^1].

[^1]: https://forum.proxmox.com/threads/how-to-best-benchmark-ssds.93543/


I used the `fio` tool to benchmark the performance of my SSDs in TrueNAS.
In the following command it is important to adapt the filename to an actual path on your zfs pool, e.g. `/mnt/yourpool/test.file`.

The following command was used:

```bash title="benchmark.sh"
#!/usr/local/bin/bash

LOGFILE="/root/benchmark.log" #filename of the logfile
FILENAME="/mnt/bigone/test/test.file" #filename of the test file


LOGFILE="/root/benchmark.log"
FILENAME="/mnt/bigone/test/test.file"


iostat | tee -a "${LOGFILE}"



fio --filename=$FILENAME --name=sync_randwrite --rw=randwrite --bs=4k --direct=1 --sync=0 --numjobs=1 --ioengine=psync --iodepth=1 --refill_buffers --size=10M --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME


fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --numjobs=1 --size=4g --iodepth=1 --runtime=60 --time_based --end_fsync=1
fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --numjobs=8 --size=4g --iodepth=8 --runtime=60 --time_based --end_fsync=1


# sync randwrite = (writes 1G)
fio --filename=$FILENAME --name=sync_randwrite --rw=randwrite --bs=4k --direct=1 --sync=1 --numjobs=1 --ioengine=psync --iodepth=1 --refill_buffers --size=1G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

# sync randread (writes 10x1G)
fio --filename=$FILENAME --name=sync_randread --rw=randread --bs=4k --direct=1 --sync=1 --numjobs=1 --ioengine=psync --iodepth=1 --refill_buffers --size=1G --loops=10 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

# seq sync seqwrite (writes 5G)
fio --filename=$FILENAME --name=sync_seqwrite --rw=write --bs=4M --direct=1 --sync=1 --numjobs=1 --ioengine=psync --iodepth=1 --refill_buffers --size=5G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

# seq sync seqread (writes 10x1G)
fio --filename=$FILENAME --name=sync_seqread --rw=read --bs=4M --direct=1 --sync=1 --numjobs=1 --ioengine=psync --iodepth=1 --refill_buffers --size=1G --loops=10 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async uncached randwrite (writes 4G)
fio --filename=$FILENAME --name=async_uncached_randwrite --rw=randwrite --bs=4k --direct=1 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async cached randwrite (writes 4G)
fio --filename=$FILENAME --name=async_cached_randwrite --rw=randwrite --bs=4k --direct=0 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async uncached randread (writes 4G)
fio --filename=$FILENAME --name=async_uncached_randread --rw=randread --bs=4k --direct=1 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=10 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async cached randread (writes 4G)
fio --filename=$FILENAME --name=async_cached_randread --rw=randread --bs=4k --direct=0 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=10 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async uncached seqwrite (writes 8G)
fio --filename=$FILENAME --name=async_uncached_seqwrite --rw=write --bs=4M --direct=1 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=2G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async cached seqwrite (writes 8G)
fio --filename=$FILENAME --name=async_cached_seqwrite --rw=write --bs=4M --direct=0 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=2G --loops=1 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async uncached seqread (writes 4G)
fio --filename=$FILENAME --name=async_uncached_seqread --rw=read --bs=4M --direct=1 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=50 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

#async cached seqread (writes 4G)
fio --filename=$FILENAME --name=async_cached_seqread --rw=read --bs=4M --direct=0 --sync=0 --numjobs=4 --ioengine=libaio --iodepth=32 --refill_buffers --size=1G --loops=50 --group_reporting | tee -a "${LOGFILE}"
rm $FILENAME

fstrim -a

sleep 60

iostat | tee -a "${LOGFILE}"
```
