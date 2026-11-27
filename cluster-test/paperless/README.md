# paperless-ngx + SMB scan drop-box

Document archive at <https://paperless.framsburg.ch>, fed by a write-only SMB share
(`smb://scan.framsburg.ch/scans`) that printers and Macs can drop files on.

```
printer / Mac ──SMB 445──▶ Traefik (entrypoint smb, LB 192.168.42.150)
                              │ IngressRouteTCP HostSNI(*)
                              ▼
                       paperless-samba ──writes──▶ PVC paperless-consume (Longhorn RWX)
                                                         ▲ polls every 10s, deletes after import
                       paperless ◀── Redis (valkey) ─────┘
                           │
                           └── CNPG cluster "paperless" (backups → MinIO)
```

## Drop-box semantics

| Action over SMB (user `scanner`)            | Result                                  |
| ------------------------------------------- | --------------------------------------- |
| Upload a new file                           | allowed                                 |
| Create a sub-folder and upload into it      | allowed (paperless consumes recursively)|
| List the share or any sub-folder            | denied                                  |
| Overwrite / rename / delete after 60s       | denied (`vfs_worm`)                     |
| Overwrite / rename own file within 60s      | allowed (grace period for slow uploads) |
| Read a file back by exact name              | allowed (known limitation, blind only)  |
| Guest login, SMB1/NT1                       | denied                                  |

How it works: `/scans` is `1000:1000` mode `3733` (setgid + sticky, no read for the
SMB user, uid 1001). New files become `scanner:paperless 0640` and new folders
`scanner:paperless 2370`. Paperless runs as uid/gid 1000 and accesses the volume
directly (not via Samba), so it can read and delete everything. The init container
re-applies the root permissions on every Samba start.

To make the share listable (e.g. if a scanner insists on browsing), change `chmod 3733`
to `chmod 3773` in `samba-deployment.yaml`.

## Prerequisites (outside git)

1. **Vault** (KV v2 under `secret/framsburg/paperless/`):
   - `app`: `secret_key` (`python3 -c "import secrets; print(secrets.token_urlsafe(64))"`),
     `admin_user`, `admin_password`
   - `oidc`: `clientId`, `clientSecret`
   - `smb`: `password` (SMB password for user `scanner`)
   - DB backups use the cluster-test group credential `secret/framsburg/test/shared/cnpg-minio-access`
     (MinIO user limited to `s3://cnpg/test/`, see docs/platform/external-secrets.md)
2. **authentik**: OAuth2/OpenID provider + application with slug `paperless`,
   redirect URI `https://paperless.framsburg.ch/accounts/oidc/authentik/login/callback/`.
3. **DNS**: `paperless.framsburg.ch` and `scan.framsburg.ch` → Traefik LB `192.168.42.150`.
4. **Traefik**: the `smb` entrypoint is exposed on port 445
   (`cluster-critical-apps/traefik/values.yaml`).

## Client setup

- **macOS**: Finder → Go → Connect to Server → `smb://scan.framsburg.ch/scans`,
  user `scanner`. The folder appears empty/unreadable by design; drag files onto it.
- **Printer / scanner**: scan-to-SMB/network folder, host `scan.framsburg.ch`,
  share `scans`, path `/` (or a sub-folder), user `scanner`, SMB2/3.

## Notes

- After the first login via authentik works, consider setting
  `PAPERLESS_DISABLE_REGULAR_LOGIN=true` / `PAPERLESS_REDIRECT_LOGIN_TO_SSO=true`.
- Samba sees Traefik's pod IP, not the client IP, so `hosts allow` only limits
  sources to the pod network and LAN.
