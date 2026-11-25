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
  gethomepage.dev/group: "Media"          # Infrastructure | Platform | Media | Utilities | RPG
  gethomepage.dev/icon: "radarr.png"      # dashboard-icons name, or mdi-<icon> / si-<icon>
  gethomepage.dev/description: "Movies"
  gethomepage.dev/pod-selector: ""        # "" = no status dot; see below
```

Optional annotations:

| Annotation | Use |
|---|---|
| `gethomepage.dev/href` | Link target when it differs from the ingress host (e.g. a sub-path) |
| `gethomepage.dev/pod-selector` | Label selector for the status dot, e.g. `app.kubernetes.io/name=argocd-server`. Without it Homepage looks for pods labelled `app.kubernetes.io/name=<ingress name>` |
| `gethomepage.dev/widget.type` | Enable a [service widget](https://gethomepage.dev/widgets/) |
| `gethomepage.dev/widget.url` | URL the widget queries (cluster-internal service URL works) |
| `gethomepage.dev/widget.key` | API key, always as a reference: `"{{HOMEPAGE_VAR_<APP>_KEY}}"` |

!!! warning "Helm templates"
    In files under `templates/`, escape the key reference so Helm doesn't evaluate it:
    `gethomepage.dev/widget.key: {{ "\"{{HOMEPAGE_VAR_ARGOCD_KEY}}\"" }}`.
    In `values.yaml` the plain string works, unless the upstream chart runs annotations through `tpl`.

Group order and layout are set in `cluster-utility-apps/homepage/templates/configmap.yaml` (`settings.yaml`).
New groups appear after the listed ones.

## Widget API keys

Keys live in Vault at `secret/framsburg/homepage` (KV v2). The ExternalSecret `homepage-api-keys` turns them into
`HOMEPAGE_VAR_*` environment variables. Reloader restarts the pod when the secret changes.

| Vault property | Where it comes from |
|---|---|
| `HOMEPAGE_VAR_ARGOCD_KEY` | ArgoCD local account `homepage` (`accounts.homepage: apiKey` in `cluster-init-apps/argo-cd/values.yaml`, read-only via `policy.default: role:readonly`) |
| `HOMEPAGE_VAR_JELLYFIN_KEY` | Jellyfin → Dashboard → API Keys |

### Create the ArgoCD token

```bash
argocd login argocd.framsburg.ch --sso          # as an fb-admins member
argocd account generate-token --account homepage
```

### Create the Jellyfin key

Jellyfin → *Dashboard* → *Advanced* → *API Keys* → **+** → app name `homepage`.

### Store them in Vault

```bash
vault kv put -mount=secret framsburg/homepage \
  HOMEPAGE_VAR_ARGOCD_KEY='<argocd token>' \
  HOMEPAGE_VAR_JELLYFIN_KEY='<jellyfin key>'
```

To add a key for another widget:

1. Add the property in Vault with `vault kv patch`, not `put`, which replaces all properties.
2. Add its name to `apiKeys.keys` in `cluster-utility-apps/homepage/values.yaml`.
3. Reference it in the annotation as `"{{HOMEPAGE_VAR_<NAME>}}"`.

## One-time setup

- **Authentik:** the forward-auth proxy provider of the embedded outpost has to cover `home.framsburg.ch`.
  - With a domain-level provider for `framsburg.ch`, nothing needs doing.
  - Otherwise, create an application plus a proxy provider (forward auth, single application) for the host and add it to
    the embedded outpost.
- **DNS:** `home.framsburg.ch` resolves like the other `*.framsburg.ch` hosts.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Service missing | Check `gethomepage.dev/enabled: "true"` is quoted. Run `kubectl -n homepage logs deploy/homepage` and look for RBAC errors. New resource kinds need a rule in `templates/clusterrole.yaml` |
| Card shows **NOT FOUND** | Pod lookup failed. Set `gethomepage.dev/pod-selector` to a matching selector, or `""` |
| Widget shows **API Error** | Key missing or wrong in Vault. Check `kubectl -n homepage get secret homepage-api-keys` and the ExternalSecret status |
| `Host validation failed` | Hostname not in `HOMEPAGE_ALLOWED_HOSTS` (set from `host` in `values.yaml`) |
