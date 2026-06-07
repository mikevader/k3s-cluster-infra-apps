# Jellyfin

Jellyfin is a free and open-source media server, deployed as a potential replacement for Plex.
Both services run in parallel sharing the same media volumes (read-only).

## Overview

| Property | Value |
|----------|-------|
| **URL** | `https://jellyfin.framsburg.ch` |
| **Port** | 8096 |
| **Image** | `jellyfin/jellyfin:10.11.10` |
| **Namespace** | `plex` (shared with Plex for PVC access) |
| **Chart** | `jellyfin/jellyfin` (3.2.0) — [official](https://github.com/jellyfin/jellyfin-helm) |
| **GPU** | NVIDIA (hardware transcoding) |
| **Node Affinity** | `k3sworker07` (same as Plex) |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              k3sworker07 (namespace: plex)           │
│                                                     │
│  ┌──────────┐          ┌──────────────┐             │
│  │   Plex   │          │   Jellyfin   │             │
│  │  :32400  │          │    :8096     │             │
│  └────┬─────┘          └──────┬───────┘             │
│       │                       │                     │
│       │  ┌────────────────────┘                     │
│       │  │                                          │
│       ▼  ▼  (read-only, same PVCs)                  │
│  ┌─────────────────────────────────────┐            │
│  │        Shared Media Volumes         │            │
│  │  plex-tv-all / plex-tv-uhd-all      │            │
│  │  plex-movies-all / plex-movies-uhd  │            │
│  │  plex-audiobooks (truenas-nfs/RWX)  │            │
│  └─────────────────────────────────────┘            │
└─────────────────────────────────────────────────────┘
```

## Volumes

### Configuration (own volume)
- **PVC**: `jellyfin-config` — 20Gi, ReadWriteOnce
- **Mount**: `/config`
- Jellyfin stores its database, metadata cache, and settings here.

### Cache
- **Type**: emptyDir
- **Mount**: `/cache`
- Transcoding cache — ephemeral, recreated on pod restart.

### Media Volumes (read-only, shared with Plex)

Jellyfin runs in the `plex` namespace and directly references the existing Plex PVCs:

| PVC Name | Mount Path |
|----------|------------|
| `plex-tv-all` | `/mnt/media/tv-all` |
| `plex-tv-uhd-all` | `/mnt/media/tv-uhd-all` |
| `plex-movies-all` | `/mnt/media/movies-all` |
| `plex-movies-uhd-all` | `/mnt/media/movies-uhd-all` |
| `plex-audiobooks` | `/mnt/media/audiobooks` |

All media volumes are mounted **read-only** to prevent accidental modification.

## Plex Metadata Migration

Watch history is migrated using [wilmardo/migrate-plex-to-jellyfin](https://github.com/wilmardo/migrate-plex-to-jellyfin),
which uses the Plex and Jellyfin APIs to transfer watched status based on file name matching.

The migration is implemented as an **ArgoCD PostSync Job** that runs automatically after the initial sync.

### Prerequisites

1. Complete the Jellyfin initial setup wizard at `https://jellyfin.framsburg.ch`
2. Add all media libraries (same paths as Plex — see volumes table above)
3. Generate a Jellyfin API key: **Dashboard → API Keys → +**
4. Get your Plex token: [support.plex.tv/articles/204059436](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/)
5. Store credentials in Vault (ExternalSecret pulls from `secret/data/framsburg/jellyfin/migration`):
   ```bash
   vault kv put secret/framsburg/jellyfin/migration \
     plex-token=<YOUR_PLEX_TOKEN> \
     jellyfin-token=<YOUR_JELLYFIN_API_KEY> \
     jellyfin-user=<YOUR_JELLYFIN_USERNAME>
   ```

### What is migrated
- Movie watch status (matched by file name)
- TV episode watch status (matched by file name)
- Uses `--skip` flag to gracefully handle unmatched items
- Uses `--translate "/mnt/media:/mnt/media"` for path mapping (same paths in both)

### Running the migration

The Job runs automatically as an ArgoCD PostSync hook on the first sync.
To trigger it again, delete the job and let ArgoCD re-sync:

```bash
kubectl -n plex delete job jellyfin-plex-migration
# ArgoCD will recreate it on next sync
```

Or run the tool directly via a one-off pod:
```bash
kubectl -n plex run plex-migrate --rm -it --image=python:3.12-slim -- /bin/sh -c '
  pip install plexapi click requests loguru &&
  cd /tmp && git clone --depth 1 https://github.com/wilmardo/migrate-plex-to-jellyfin.git &&
  cd migrate-plex-to-jellyfin &&
  python3 migrate.py \
    --plex-url http://plex:32400 \
    --plex-token <PLEX_TOKEN> \
    --jellyfin-url http://jellyfin-jellyfin:8096 \
    --jellyfin-token <JELLYFIN_TOKEN> \
    --jellyfin-user <USER> \
    --skip --insecure --debug \
    --translate "/mnt/media:/mnt/media"
'
```

### Monitoring the migration
```bash
kubectl -n plex logs job/jellyfin-plex-migration -f
```

### For managed Plex users
If migrating a specific managed user's watch state, add `--plex-managed-user <name>`.

## Hardware Transcoding

Jellyfin is configured with NVIDIA GPU access for hardware-accelerated transcoding:
- `runtimeClassName: nvidia`
- `NVIDIA_VISIBLE_DEVICES: all`
- `NVIDIA_DRIVER_CAPABILITIES: all`
- GPU limit: 1 × `nvidia.com/gpu`

After first login, enable hardware transcoding in:
**Dashboard → Playback → Transcoding → Hardware acceleration: NVIDIA NVENC**

## Initial Setup

1. Push changes to `k3s-cluster-infra-apps` — ArgoCD will automatically sync and deploy Jellyfin into the `plex` namespace.

2. Access `https://jellyfin.framsburg.ch` and complete the setup wizard.

3. Add media libraries pointing to:
   - `/mnt/media/tv-all` — TV Shows
   - `/mnt/media/tv-uhd-all` — TV Shows (4K)
   - `/mnt/media/movies-all` — Movies
   - `/mnt/media/movies-uhd-all` — Movies (4K)
   - `/mnt/media/audiobooks` — Audiobooks

4. Enable hardware transcoding (see section above).

5. Store migration credentials in Vault (see migration section) — the ExternalSecret
   will automatically sync them into the cluster.

6. The PostSync migration Job will run automatically on the next ArgoCD sync.

## Comparison with Plex

| Feature | Plex | Jellyfin |
|---------|------|----------|
| License | Proprietary (freemium) | FOSS (GPL-2.0) |
| Transcoding | NVIDIA GPU | NVIDIA GPU |
| Remote Access | Built-in relay | Direct / reverse proxy |
| Mobile Apps | Paid unlock | Free |
| Live TV/DVR | Plex Pass | Free (with tuner) |
| Plugins | Limited | Extensive |
| Auth | Plex account | Local or LDAP/SSO |

## Troubleshooting

### Pod not starting
```bash
kubectl -n plex describe pod -l app.kubernetes.io/name=jellyfin
kubectl -n plex logs -l app.kubernetes.io/name=jellyfin
```

### Migration job failing
```bash
kubectl -n plex logs job/jellyfin-plex-migration
kubectl -n plex describe job jellyfin-plex-migration
```

### GPU not detected
Verify the NVIDIA device plugin is running and the node has GPU resources:
```bash
kubectl describe node k3sworker07 | grep -A5 nvidia
```

## Network

- Internal: `http://jellyfin.plex.svc.cluster.local:8096`
- External: `https://jellyfin.framsburg.ch` (via Traefik ingress with Authentik SSO)





