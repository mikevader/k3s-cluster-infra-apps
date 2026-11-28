# Homepage

Start page for all cluster services at <https://home.framsburg.ch>, powered by
[Homepage](https://gethomepage.dev) (gethomepage).

- **Chart:** `cluster-utility-apps/homepage` (local chart, no upstream dependency)
- **Namespace:** `homepage`
- **Auth:** Traefik middleware `authentik-authentik@kubernetescrd` (Authentik forward-auth)
- **Discovery:** reads `gethomepage.dev/*` annotations from Ingresses, Traefik IngressRoutes and HTTPRoutes
  cluster-wide (read-only ClusterRole)

Everybody who passes the Authentik login sees every service. Access to each service is still enforced by that
service's own auth. See [the decision record](../adr/homepage-dashboard.md) for why.

## Adding a service

Add annotations to the service's Ingress/IngressRoute in git. There is nothing to configure in the Homepage UI.

```yaml
annotations:
  gethomepage.dev/enabled: "true"
  gethomepage.dev/name: "Radarr"
  # group: one of the groups in the table below
  gethomepage.dev/group: "Media Automation"
  # icon: dashboard-icons name, or mdi-<icon> / si-<icon>
  gethomepage.dev/icon: "radarr.png"
  gethomepage.dev/description: "Movies"
  gethomepage.dev/pod-selector: ""        # "" = no status dot; see below
```

Optional annotations:

| Annotation | Use |
| --- | --- |
| `gethomepage.dev/href` | Link target when it differs from the ingress host (e.g. a sub-path) |
| `gethomepage.dev/pod-selector` | Label selector for the status dot, e.g. `app.kubernetes.io/name=argocd-server`. Without it Homepage looks for pods labelled `app.kubernetes.io/name=<ingress name>` |
| `gethomepage.dev/widget.type` | Enable a [service widget](https://gethomepage.dev/widgets/) |
| `gethomepage.dev/widget.url` | URL the widget queries (cluster-internal service URL works) |
| `gethomepage.dev/widget.key` | API key, always as a reference: `"{{HOMEPAGE_VAR_<APP>_KEY}}"` |

!!! warning "Helm templates"
    In files under `templates/`, escape the key reference so Helm doesn't evaluate it:
    `gethomepage.dev/widget.key: {{ "\"{{HOMEPAGE_VAR_ARGOCD_KEY}}\"" }}`.
    In `values.yaml` the plain string works, unless the upstream chart runs annotations through `tpl`.

## Groups and tabs

Services are grouped by what you go there to do. The **Home** tab holds everyday apps; **Admin** holds the tools
for running the cluster. Everyone who passes Authentik sees both tabs.

| Tab | Group | For |
| --- | --- | --- |
| Home | Watch | Streaming and media requests (Plex, Jellyfin, Seerr) |
| Home | Household | Finance, recipes, documents (Actual, Mealie, Paperless) |
| Home | RPG | Tabletop tools (DM Workshop, Foundry VTT) |
| Admin | Media Automation | *arr apps, Tautulli, Filebrowser |
| Admin | Downloads | Download clients (Transmission, Flood, SABnzbd) |
| Admin | Cluster | Argo CD, Headlamp, Traefik, Longhorn |
| Admin | Observability | Grafana, Prometheus, Alertmanager, Uptime Kuma |
| Admin | Identity & Secrets | Authentik, Vault |
| Admin | Lab | Test and debug tools (httpbin) |

Group order, tabs and columns are set in `layout` of `settings.yaml` in
`cluster-utility-apps/homepage/templates/configmap.yaml`. A group that isn't listed there ends up on the first tab,
so add new groups to `layout` with their `tab`.

## Bookmarks

External links live in `bookmarks.yaml` in the same ConfigMap. Bookmark groups are laid out like service groups:

- **Home:** Weather & Travel (MeteoSwiss, SBB), RPG Reference (D&D Beyond, 5e.tools, Kobold Plus Fight Club)
- **Admin:** GitOps (GitHub repos, Renovate dashboard, GHCR, docs), Network (OPNsense, TrueNAS), References

Apps deployed from `cluster-test/` start their description with `🧪 Test · ` so they stand out on the dashboard.

The header shows the cluster and per-node CPU/memory (`kubernetes`), Longhorn storage (`longhorn`, via the in-cluster
`longhorn-frontend` service, URL under `providers.longhorn` in `settings.yaml`) and the Open-Meteo weather for Basel
(`openmeteo`), set in `widgets.yaml`.
The background image URL is `background.image` in `values.yaml`.

## Widget API keys

Keys live in Vault at `secret/framsburg/homepage` (KV v2). The ExternalSecret `homepage-api-keys` turns **every**
property there into an environment variable of the same name (`dataFrom.extract`). Reloader restarts the pod when the
secret changes.

| Vault property | Where it comes from |
| --- | --- |
| `HOMEPAGE_VAR_ARGOCD_KEY` | ArgoCD local account `homepage` (`accounts.homepage: apiKey` in `cluster-init-apps/argo-cd/values.yaml`, read-only via `policy.default: role:readonly`) |
| `HOMEPAGE_VAR_JELLYFIN_KEY` | Jellyfin → Dashboard → API Keys |
| `HOMEPAGE_VAR_PLEX_KEY` | Plex token of the server owner (see below) |
| `HOMEPAGE_VAR_RADARR_KEY` | Radarr → Settings → General → API Key |
| `HOMEPAGE_VAR_SONARR_KEY` | Sonarr → Settings → General → API Key |
| `HOMEPAGE_VAR_RADARR_4K_KEY` | Radarr 4K → Settings → General → API Key |
| `HOMEPAGE_VAR_SONARR_4K_KEY` | Sonarr 4K → Settings → General → API Key |
| `HOMEPAGE_VAR_PROWLARR_KEY` | Prowlarr → Settings → General → API Key |
| `HOMEPAGE_VAR_SEERR_KEY` | Seerr → Settings → General → API Key |
| `HOMEPAGE_VAR_SABNZBD_KEY` | SABnzbd → Config → General → API Key |
| `HOMEPAGE_VAR_MEALIE_KEY` | Mealie → Profile → Manage Your API Tokens (see below) |
| `HOMEPAGE_VAR_AUTHENTIK_KEY` | Authentik API token of a read-only service account (see below) |

Widgets call the apps on their in-cluster service URL, which bypasses the Authentik forward-auth middleware.
SABnzbd is the exception: its host whitelist rejects the service hostname, so the widget uses
`https://sabnzbd.framsburg.ch`.

### Create the ArgoCD token

`argocd-secret` is fully owned by the `argocd-secret-ext` ExternalSecret
(`cluster-init-apps/argo-cd/templates/argocd-secret-ext.yaml`). It rewrites the
secret from Vault every minute.

ArgoCD only accepts a token whose ID is listed in `accounts.homepage.tokens`. The
entry that `argocd account generate-token` writes disappears on the next refresh,
so the token ID list lives in Vault as well (`secret/framsburg/argocd/secrets`).
Without it the widget gets **401**.

1. As an `fb-admins` member, generate the token straight into Vault:

    ```bash
    argocd login argocd.framsburg.ch --sso --grpc-web
    vault kv patch -mount=secret framsburg/homepage \
      HOMEPAGE_VAR_ARGOCD_KEY="$(argocd account generate-token \
        --account homepage)"
    ```

    If the SSO session is broken, add `--core` to `generate-token`. Core mode
    uses your kubeconfig, which must be set to the `argocd-system` namespace.

2. Store the token ID, built from the token's `jti` and `iat` claims:

    ```bash
    TOKEN=$(vault kv get -mount=secret -field=HOMEPAGE_VAR_ARGOCD_KEY \
      framsburg/homepage)
    TOKENS=$(python3 - "$TOKEN" <<'EOF'
    import sys, json, base64
    p = sys.argv[1].split(".")[1]
    p += "=" * (-len(p) % 4)
    c = json.loads(base64.urlsafe_b64decode(p))
    print(json.dumps([{"id": c["jti"], "iat": c["iat"]}]))
    EOF
    )
    vault kv patch -mount=secret framsburg/argocd/secrets \
      accounts.homepage.tokens="$TOKENS"
    unset TOKEN TOKENS
    ```

!!! warning
    Write the Vault property before an ExternalSecret references it. If a
    referenced property is missing, `argocd-secret-ext` stops updating
    `argocd-secret`, which also holds the admin password and OIDC keys.

### Create the Jellyfin key

Jellyfin → *Dashboard* → *Advanced* → *API Keys* → **+** → app name `homepage`.

### Get the Plex token

Use one of these:

- In Plex Web, open any library item → **⋯** → *Get Info* → *View XML*. The URL ends in `X-Plex-Token=<token>`.
- From the server's `Preferences.xml`, read the `PlexOnlineToken` attribute:

```bash
kubectl -n plex exec deploy/plex -- \
  grep -o 'PlexOnlineToken="[^"]*"' \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"
```

The token belongs to the Plex account, so treat it like a password.

### Read the *arr, Seerr and SABnzbd keys

These apps keep the key in their config file, so it can go straight into Vault:

```bash
key() { kubectl -n plex exec deploy/"$1" -c "$1" -- cat /config/config.xml | sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p'; }
vault kv patch -mount=secret framsburg/homepage \
  HOMEPAGE_VAR_RADARR_KEY="$(key arr-radarr)" \
  HOMEPAGE_VAR_SONARR_KEY="$(key arr-sonarr)" \
  HOMEPAGE_VAR_RADARR_4K_KEY="$(key arr-radarr-4k)" \
  HOMEPAGE_VAR_SONARR_4K_KEY="$(key arr-sonarr-4k)" \
  HOMEPAGE_VAR_PROWLARR_KEY="$(key arr-prowlarr)" \
  HOMEPAGE_VAR_SEERR_KEY="$(kubectl -n plex exec deploy/arr-overseerr -- cat /app/config/settings.json | jq -r .main.apiKey)" \
  HOMEPAGE_VAR_SABNZBD_KEY="$(kubectl -n plex exec deploy/sabnzbd -- sed -n 's/^api_key = //p' /config/sabnzbd.ini)"
```

### Create the Mealie token

Mealie API tokens belong to a user and carry that user's rights. In Mealie, open your profile → *Manage Your API
Tokens*, enter the name `homepage` and click *Generate*. The token is shown only once:

```bash
vault kv patch -mount=secret framsburg/homepage HOMEPAGE_VAR_MEALIE_KEY='<mealie token>'
```

### Create the Authentik token

Use a dedicated service account with view-only permissions instead of an admin token:

1. *Admin interface* → *Directory* → *Users* → *New Service Account*: username `homepage`, untick *Create group*,
   untick *Expiring*. Ignore the token it shows.
2. *Directory* → *Roles* → *Create*: name `homepage-readonly`. Open the role → *Permissions* → *Assign permission*
   and add these global permissions:
   - *authentik Core* → *Can view User*
   - *authentik Events* → *Can view Event*
3. Give the `homepage` user that role (user → *Roles* → *Assign role*). Authentik ≥ 2025.12 grants permissions only
   through roles; without it the widget gets **403**.
4. *Directory* → *Tokens and App passwords* → *Create*: identifier `homepage`, user `homepage`, intent **API Token**,
   untick *Expiring*. Copy the key with the copy button in the token list.

```bash
vault kv patch -mount=secret framsburg/homepage HOMEPAGE_VAR_AUTHENTIK_KEY='<authentik token>'
```

### Store them in Vault

```bash
vault kv put -mount=secret framsburg/homepage \
  HOMEPAGE_VAR_ARGOCD_KEY='<argocd token>' \
  HOMEPAGE_VAR_JELLYFIN_KEY='<jellyfin key>' \
  HOMEPAGE_VAR_PLEX_KEY='<plex token>'
```

To add a key for another widget:

1. Add the property in Vault with `vault kv patch`, not `put`, which replaces all properties.
2. Reference it in the annotation as `"{{HOMEPAGE_VAR_<NAME>}}"`.

The ExternalSecret refreshes hourly. To pick up a new key right away:
`kubectl -n homepage annotate externalsecret homepage-api-keys force-sync=$(date +%s) --overwrite`.

## One-time setup

- **Authentik:** the forward-auth proxy provider of the embedded outpost has to cover `home.framsburg.ch`.
  - With a domain-level provider for `framsburg.ch`, nothing needs doing.
  - Otherwise, create an application plus a proxy provider (forward auth, single application) for the host and add it to
    the embedded outpost.
- **DNS:** `home.framsburg.ch` resolves like the other `*.framsburg.ch` hosts.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Service missing | Check `gethomepage.dev/enabled: "true"` is quoted. Run `kubectl -n homepage logs deploy/homepage` and look for RBAC errors. New resource kinds need a rule in `templates/clusterrole.yaml` |
| Card shows **NOT FOUND** | Pod lookup failed. Set `gethomepage.dev/pod-selector` to a matching selector, or `""` |
| Jellyfin widget 404 on `/emby/...` | Jellyfin ≥ 10.12 needs `gethomepage.dev/widget.version: "2"` |
| ArgoCD widget **401** with a valid token | Token ID missing from `accounts.homepage.tokens` in Vault (see *Create the ArgoCD token*) |
| Widget shows **API Error** | Key missing or wrong in Vault. Check `kubectl -n homepage get secret homepage-api-keys` and the ExternalSecret status |
| `Host validation failed` | Hostname not in `HOMEPAGE_ALLOWED_HOSTS` (set from `host` in `values.yaml`) |
