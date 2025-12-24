

# HL15

Yes, finally, the big package is here of my HL15.

## Houston UI

After some trials and errors I decided to not use the Houston UI for the HL15. The reason is simple:
I tried several times to create a new pool with the Houston UI, but it always failed. And after I saw that a lot of the
other features, adding additional applications, are quite manual, I decided to not use it.

## Boot from USB with VGA?!?!?!?!?

Yes the XL11HSP board has only a VGA port and no HDMI. I think I recycled my last VGA capable anything in 2010.
So I can either buy an adapter or an inexpensive video card.

... or use the IPMI interface of the board.
‡
## IPMI to the rescue

One of the hard parts was to find the PWD and USERNAME for the IPMI interface. Username is `ADMIN` and yes its case-sensitive.
The password is on a sticker on the side of the chassis. But there are a lot of other places where you can find it[^1].
Or find something in the manual[^2].
[^1]: https://www.supermicro.com/support/BMC_Unique_Password_Guide.pdf
[^2]: https://www.supermicro.com/manuals/motherboard/C620/MNL-1949.pdf


## DNS Name

* Define the DHCP reservation for the TrueNAS server
* Add the DNS entry for the TrueNAS server and minio
* Add the ACME Certificate for TrueNAS and minio


## Certificates

* Create new API Key in TrueNAS to upload ACME Certificates
* Store the API Key in a safe place (e.g. Vault)


## TrueNAS

1. Update TrueNAS to the latest version
2. Add Pool 6 disks raidz2
3. Enable Services
   * NFS
   * iSCSI
   * SMB
     * Enable Apple SMB2/3 Protocol
   * SSH
4. Add Dataset
   * 'TimeMachine' for Time Machine backups
   * 'K8S' for Kubernetes
     * 'NFS' for NFS share
   * 'Minio' for Minio

## K8S

Add the csi driver config to the secret.
Add an NFS share to the TrueNAS server for the K8S cluster.



## Perf Test

### Network
first looking for iperf3 --> super high even from within container


### Storage Large files

```
fio --name=plex_video_sim \
    --directory=/mnt/bigone/test \  
    --size=100g \
    --filesize=2g \
    --nrfiles=50 \
    --rw=write \
    --bs=1m \
    --ioengine=posixaio \
    --direct=1 \
    --sync=1 \
    --time_based \
    --runtime=60s
```

```
plex_video_sim: (g=0): rw=write, bs=(R) 1024KiB-1024KiB, (W) 1024KiB-1024KiB, (T) 1024KiB-1024KiB, ioengine=posixaio, iodepth=1
fio-3.33
Starting 1 process
plex_video_sim: Laying out IO files (50 files / total 102400MiB)
Jobs: 1 (f=50): [W(1)][100.0%][w=35.0MiB/s][w=35 IOPS][eta 00m:00s]
plex_video_sim: (groupid=0, jobs=1): err= 0: pid=53362: Tue Jun  3 15:17:19 2025
  write: IOPS=39, BW=39.9MiB/s (41.9MB/s)(2397MiB/60040msec); 0 zone resets
    slat (usec): min=21, max=174, avg=61.51, stdev=11.25
    clat (msec): min=7, max=252, avg=24.98, stdev=23.16
     lat (msec): min=7, max=252, avg=25.04, stdev=23.16
    clat percentiles (msec):
     |  1.00th=[    9],  5.00th=[   10], 10.00th=[   10], 20.00th=[   11],
     | 30.00th=[   11], 40.00th=[   12], 50.00th=[   13], 60.00th=[   16],
     | 70.00th=[   31], 80.00th=[   45], 90.00th=[   56], 95.00th=[   63],
     | 99.00th=[  117], 99.50th=[  144], 99.90th=[  230], 99.95th=[  236],
     | 99.99th=[  253]
   bw (  KiB/s): min=10240, max=77824, per=100.00%, avg=40891.73, stdev=10702.60, samples=120
   iops        : min=   10, max=   76, avg=39.93, stdev=10.45, samples=120
  lat (msec)   : 10=15.10%, 20=48.98%, 50=20.73%, 100=13.98%, 250=1.17%
  lat (msec)   : 500=0.04%
  cpu          : usr=0.31%, sys=0.08%, ctx=2400, majf=3, minf=24
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,2397,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=39.9MiB/s (41.9MB/s), 39.9MiB/s-39.9MiB/s (41.9MB/s-41.9MB/s), io=2397MiB (2513MB), run=60040-60040msec
```

| Metric                        | Value                   | Meaning                                                           |
| ----------------------------- | ----------------------- | ----------------------------------------------------------------- |
| **Bandwidth (BW)**            | 39.9 MiB/s (≈41.9 MB/s) | Raw sustained write speed                                         |
| **IOPS**                      | \~40                    | Expected for large 1 MB-block sync writes                         |
| **Average latency**           | \~25 ms                 | Time per write — fairly high for a 1 MB write                     |
| **99.9th percentile latency** | 230+ ms                 | High tail latency (bad for apps expecting consistent performance) |
| **CPU usage**                 | Very low                | Not CPU-bound                                                     |


do it again without sync:

```
plex_video_sim: (g=0): rw=write, bs=(R) 1024KiB-1024KiB, (W) 1024KiB-1024KiB, (T) 1024KiB-1024KiB, ioengine=posixaio, iodepth=1
fio-3.33
Starting 1 process
plex_video_sim: Laying out IO files (50 files / total 102400MiB)
Jobs: 1 (f=50): [W(1)][100.0%][w=587MiB/s][w=586 IOPS][eta 00m:00s]
plex_video_sim: (groupid=0, jobs=1): err= 0: pid=55577: Tue Jun  3 15:52:25 2025
  write: IOPS=591, BW=591MiB/s (620MB/s)(34.7GiB/60002msec); 0 zone resets
    slat (usec): min=12, max=7722, avg=71.24, stdev=52.76
    clat (nsec): min=1366, max=40612k, avg=1614990.31, stdev=1045881.15
     lat (usec): min=178, max=40699, avg=1686.23, stdev=1052.83
    clat percentiles (usec):
     |  1.00th=[  192],  5.00th=[  239], 10.00th=[  498], 20.00th=[ 1237],
     | 30.00th=[ 1369], 40.00th=[ 1450], 50.00th=[ 1549], 60.00th=[ 1663],
     | 70.00th=[ 1827], 80.00th=[ 2057], 90.00th=[ 2376], 95.00th=[ 2671],
     | 99.00th=[ 4080], 99.50th=[ 6456], 99.90th=[13173], 99.95th=[14353],
     | 99.99th=[34341]
   bw (  KiB/s): min=250401, max=3360768, per=100.00%, avg=605677.13, stdev=319260.06, samples=119
   iops        : min=  244, max= 3282, avg=591.45, stdev=311.75, samples=119
  lat (usec)   : 2=0.01%, 250=5.73%, 500=4.33%, 750=3.84%, 1000=1.45%
  lat (msec)   : 2=62.60%, 4=21.01%, 10=0.80%, 20=0.21%, 50=0.03%
  cpu          : usr=4.70%, sys=0.79%, ctx=38587, majf=1, minf=28
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,35488,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=591MiB/s (620MB/s), 591MiB/s-591MiB/s (620MB/s-620MB/s), io=34.7GiB (37.2GB), run=60002-60002msec
```

with slog:

```
plex_video_sim: (g=0): rw=write, bs=(R) 1024KiB-1024KiB, (W) 1024KiB-1024KiB, (T) 1024KiB-1024KiB, ioengine=posixaio, iodepth=1
fio-3.33
Starting 1 process
plex_video_sim: Laying out IO files (50 files / total 102400MiB)
Jobs: 1 (f=50): [W(1)][100.0%][w=453MiB/s][w=453 IOPS][eta 00m:00s]
plex_video_sim: (groupid=0, jobs=1): err= 0: pid=58033: Tue Jun  3 16:13:08 2025
write: IOPS=459, BW=460MiB/s (482MB/s)(27.0GiB/60003msec); 0 zone resets
slat (usec): min=15, max=1862, avg=59.12, stdev=35.96
clat (usec): min=1041, max=73633, avg=2109.98, stdev=1213.42
lat (usec): min=1509, max=73730, avg=2169.11, stdev=1214.60
clat percentiles (usec):
|  1.00th=[ 1598],  5.00th=[ 1696], 10.00th=[ 1778], 20.00th=[ 1876],
| 30.00th=[ 1926], 40.00th=[ 1975], 50.00th=[ 2008], 60.00th=[ 2040],
| 70.00th=[ 2073], 80.00th=[ 2114], 90.00th=[ 2245], 95.00th=[ 2442],
| 99.00th=[ 7504], 99.50th=[ 7898], 99.90th=[13304], 99.95th=[21627],
| 99.99th=[69731]
bw (  KiB/s): min=387072, max=522240, per=100.00%, avg=471227.66, stdev=20051.34, samples=119
iops        : min=  378, max=  510, avg=460.18, stdev=19.57, samples=119
lat (msec)   : 2=48.09%, 4=50.63%, 10=1.13%, 20=0.08%, 50=0.05%
lat (msec)   : 100=0.02%
cpu          : usr=3.10%, sys=0.65%, ctx=28811, majf=0, minf=24
IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
issued rwts: total=0,27599,0,0 short=0,0,0,0 dropped=0,0,0,0
latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
WRITE: bw=460MiB/s (482MB/s), 460MiB/s-460MiB/s (482MB/s-482MB/s), io=27.0GiB (28.9GB), run=60003-60003msec
```



### Storage small files

```
fio --name=plex_meta_sim \
    --directory=/mnt/bigone/test \
    --size=1g \ 
    --filesize=16k-512k \
    --nrfiles=1000 \ 
    --rw=write \
    --bs=8k \
    --ioengine=posixaio \
    --direct=1 \
    --sync=1 \
    --time_based \
    --runtime=60s
```

```
plex_meta_sim: (g=0): rw=write, bs=(R) 8192B-8192B, (W) 8192B-8192B, (T) 8192B-8192B, ioengine=posixaio, iodepth=1
fio-3.33
Starting 1 process
plex_meta_sim: Laying out IO files (1000 files / total 258MiB)
Jobs: 1 (f=936): [W(1)][100.0%][w=648KiB/s][w=81 IOPS][eta 00m:00s]  
plex_meta_sim: (groupid=0, jobs=1): err= 0: pid=54783: Tue Jun  3 15:39:56 2025
  write: IOPS=102, BW=819KiB/s (839kB/s)(48.0MiB/60003msec); 0 zone resets
    slat (usec): min=3, max=231, avg= 9.29, stdev= 3.17
    clat (msec): min=3, max=189, avg= 9.73, stdev= 8.30
     lat (msec): min=3, max=189, avg= 9.74, stdev= 8.30
    clat percentiles (msec):
     |  1.00th=[    5],  5.00th=[    5], 10.00th=[    5], 20.00th=[    9],
     | 30.00th=[    9], 40.00th=[    9], 50.00th=[    9], 60.00th=[    9],
     | 70.00th=[   10], 80.00th=[   12], 90.00th=[   12], 95.00th=[   17],
     | 99.00th=[   34], 99.50th=[   50], 99.90th=[  144], 99.95th=[  157],
     | 99.99th=[  190]
   bw (  KiB/s): min=  288, max= 1344, per=100.00%, avg=820.84, stdev=166.17, samples=119
   iops        : min=   36, max=  168, avg=102.61, stdev=20.77, samples=119
  lat (msec)   : 4=0.02%, 10=72.21%, 20=25.35%, 50=1.94%, 100=0.23%
  lat (msec)   : 250=0.26%
  cpu          : usr=0.20%, sys=0.31%, ctx=6147, majf=0, minf=33
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,6142,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=819KiB/s (839kB/s), 819KiB/s-819KiB/s (839kB/s-839kB/s), io=48.0MiB (50.3MB), run=60003-60003msec
```

do it again with

`zfs set sync=disabled bigone/test`

```
```



with slog:

```
plex_meta_sim: (g=0): rw=write, bs=(R) 8192B-8192B, (W) 8192B-8192B, (T) 8192B-8192B, ioengine=posixaio, iodepth=1
fio-3.33
Starting 1 process
plex_meta_sim: Laying out IO files (1000 files / total 258MiB)
Jobs: 1 (f=809): [W(1)][100.0%][w=6760KiB/s][w=845 IOPS][eta 00m:00s]
plex_meta_sim: (groupid=0, jobs=1): err= 0: pid=58442: Tue Jun  3 16:16:21 2025
  write: IOPS=781, BW=6252KiB/s (6402kB/s)(366MiB/60001msec); 0 zone resets
    slat (usec): min=2, max=7450, avg= 8.89, stdev=35.10
    clat (usec): min=863, max=12230, avg=1261.01, stdev=207.62
     lat (usec): min=866, max=12393, avg=1269.90, stdev=212.02
    clat percentiles (usec):
     |  1.00th=[  963],  5.00th=[ 1074], 10.00th=[ 1123], 20.00th=[ 1188],
     | 30.00th=[ 1221], 40.00th=[ 1254], 50.00th=[ 1270], 60.00th=[ 1287],
     | 70.00th=[ 1303], 80.00th=[ 1336], 90.00th=[ 1352], 95.00th=[ 1369],
     | 99.00th=[ 1418], 99.50th=[ 1450], 99.90th=[ 2835], 99.95th=[ 5932],
     | 99.99th=[11076]
   bw (  KiB/s): min= 5984, max= 6928, per=99.97%, avg=6250.89, stdev=175.37, samples=119
   iops        : min=  748, max=  866, avg=781.36, stdev=21.92, samples=119
  lat (usec)   : 1000=2.08%
  lat (msec)   : 2=97.73%, 4=0.13%, 10=0.05%, 20=0.01%
  cpu          : usr=1.57%, sys=1.55%, ctx=46989, majf=0, minf=36
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,46888,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=6252KiB/s (6402kB/s), 6252KiB/s-6252KiB/s (6402kB/s-6402kB/s), io=366MiB (384MB), run=60001-60001msec
```






Resources: go back to [Houston UI](https://knowledgebase.45drives.com/kb/kb450470-rocky-linux-houston-ui-installation/)


rsync -avh --progress /mnt/media_drive/movies/ /mnt/plex_storage/movies/

rsync --dry-run -ravh --progress 
rsync   -ravh --progress /proc/1/root/media7/ /proc/1/root/media-all/

Debugging:
* kubectl -n hidden debug whisparr-5b5d685499-pvgjp -it --image=busybox --share-processes --target=whisparr
* ln -s /proc/$$/root/bin /proc/1/.cdebug
* export PATH=$PATH:/ .cdebug
* chroot /proc/1/root/
