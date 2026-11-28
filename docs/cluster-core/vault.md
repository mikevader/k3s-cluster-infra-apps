# Hashicorp Vault

For operating the Vault inside K8S it is a good idea to use the [Banzaicloud Vault-Operator](https://github.com/banzaicloud/bank-vaults).
It automates some the integration and HA tasks.


## Install the operator

Define a new Chart with a dependencies to the
[Vault-Operator Chart](https://artifacthub.io/packages/helm/banzaicloud-stable/vault-operator)
in the app of apps for the vault-operator with the following values:

```yaml
vault-operator:
  crdAnnotations:
      "helm.sh/hook": crd-install
```

## Install Vault

Define a new empty Chart with the following templates inside:

```yaml:rbac.yaml
kind: ServiceAccount
apiVersion: v1
metadata:
  name: vault

---

kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vault
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "update", "patch"]
---

kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vault
roleRef:
  kind: Role
  name: vault
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: ServiceAccount
    name: vault

---

# This binding allows the deployed Vault instance to authenticate clients
# through Kubernetes ServiceAccounts (if configured so).
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault
    namespace: default
```

## Use secrets

You always have to map the secrets in different ways. You can find a detailed
description on [banzais website](https://banzaicloud.com/docs/bank-vaults/mutating-webhook/)

### As envrionment variable

Pod should have the following annotations:

```yaml
annotations:
  vault.security.banzaicloud.io/vault-addr: "http://vault.vault.svc:8200"
  vault.security.banzaicloud.io/vault-path: "kubernetes"
  vault.security.banzaicloud.io/vault-role: "test"
  vault.security.banzaicloud.io/vault-skip-verify: "true"
```

You should adapt the role to the corresponding role you want to use.
You can then use secrets in environment variables like this:

```yaml
env:
  - name: GITHUB_CLIENT_ID
    value: vault:secret/data/framsburg/test#github_token
```

### As secret

The approach with secrets looks quite similar. The main difference is, that you
have to provide the path to the secret **base64** encoded.

```bash
$ echo -n vault:secret/data/framsburg/test#github_token | base64
dmF1bHQ6c2VjcmV0L2RhdGEvZnJhbXNidXJnL3Rlc3QjZ2l0aHViX3Rva2Vu
```

Then prepare the secret accodringly:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: some-secret
data:
  GITHUB_CLIENT_ID: dmF1bHQ6c2VjcmV0L2RhdGEvZnJhbXNidXJnL3Rlc3QjZ2l0aHViX3Rva2Vu
type: Opaque
```

### Inline

Instead of environment variables or secrets you can use the vault key reference
anywhere in resources and the webhook will replace it with the secret.


## CLI access

The `vault` CLI reads the server address from `VAULT_ADDR`. There is no config
file for it. Set it in `~/.zshrc`, including the scheme:

```bash
export VAULT_ADDR=https://vault.framsburg.ch
```

Log in through Authentik:

```bash
vault login -method=oidc
```

This opens the browser and receives the callback on
`http://localhost:8250/oidc/callback`. The token lands in `~/.vault-token`
and is valid for 1h. Check it with `vault token lookup`.

The callback URL must be allowed in two places:

- the Vault OIDC role (`allowed_redirect_uris` in
  `cluster-platform-apps/vault/templates/cr-raft.yaml`)
- the redirect URIs of the Vault provider in Authentik, which you set up by
  hand

If either one is missing, the login fails with a redirect URI error.

Logins get the `allow_secrets` policy. It includes the `patch` capability, so
`vault kv patch` works on KV v2. Without `patch`, use
`vault kv patch -method=rw`, which only needs `read` and `update`.

## Policies and roles

Workloads only read secrets, and only under `secret/framsburg/`; everything else in the
`secret` mount is for OIDC logins. Which store reads which path is described in
[External Secrets → Secret layout](../platform/external-secrets.md#secret-layout-in-vault).
Removed roles and policies must be deleted by hand, see
[Setup Store](../platform/external-secrets.md#setup-store).

## Monitoring

* https://github.com/hashicorp/vault/issues/13978
* https://developer.hashicorp.com/vault/tutorials/monitoring/monitor-telemetry-grafana-prometheus
* https://developer.hashicorp.com/vault/tutorials/monitoring/usage-metrics

## Operations

Vault runs as a 3-node raft cluster (`vault-0..2` in namespace `vault`), managed by the
bank-vaults operator (`cluster-platform-apps/vault-operator`) from the `Vault` CR in
`cluster-platform-apps/vault/templates/cr-raft.yaml`.

Most commands below need the root token. This helper runs the Vault CLI on a pod
without printing the token:

```bash
v() { kubectl -n vault exec vault-2 -c vault -- env VAULT_ADDR=http://127.0.0.1:8200 \
  VAULT_TOKEN="$(kubectl -n vault get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)" vault "$@"; }
```

If `vault-2` is the broken node, change the pod in the helper to a healthy one.

### Health check

Run this before and after every change:

```bash
kubectl -n vault get pods                       # all vault-X pods 3/3
v operator raft list-peers                      # 3 voters, one leader
v operator raft autopilot state | grep -E '^Healthy|Failure Tolerance'   # true / 1
for p in vault-0 vault-1 vault-2; do
  kubectl -n vault exec $p -c vault -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status' \
    | grep -E 'Version|Sealed|Applied Index'
done                                            # same version, unsealed, same index
kubectl get externalsecret -A                   # all Ready=True
```

Also log in once through OIDC at https://vault.framsburg.ch.

**Do not start an upgrade unless all three nodes are healthy.** A rolling restart takes
one node down at a time, and with only two healthy nodes that loses quorum.

### Upgrading Vault

1. **Check the health** (see above). If a node is crash-looping, fix it first (see
   [Recovering a corrupted raft node](#recovering-a-corrupted-raft-node)).
2. **Take a snapshot** and copy it off the cluster. Store it outside this repo: it
   contains the (encrypted) contents of the whole Vault.
   ```bash
   v operator raft snapshot save /tmp/vault.snap
   kubectl -n vault cp -c vault vault-2:/tmp/vault.snap ./vault-$(date +%F).snap
   kubectl -n vault exec vault-2 -c vault -- rm /tmp/vault.snap
   ```
3. **Read the release notes** for every version you pass, especially the
   [important changes](https://developer.hashicorp.com/vault/docs/updates/important-changes)
   page, and check the operator's
   [compatibility table](https://github.com/bank-vaults/vault-operator/blob/main/VERSIONS.md).
4. **Bump the operator / bank-vaults sidecar first**, if needed, as a separate commit:
   - Operator: `version` in `cluster-platform-apps/vault-operator/Chart.yaml`.
   - Sidecar: `bankVaults.image.tag` in `cluster-platform-apps/vault-operator/values.yaml`.

   Wait until the pods have rolled and the health check passes.
5. **Bump `image:` in `cr-raft.yaml`**, one hop at a time for big jumps (for example
   1.20 → 1.21 → 2.x), and push. The operator then restarts the pods one by one,
   highest ordinal first. Wait until each pod is unsealed on the new version before
   moving on, and run the full health check after each hop.

**Rollback:** do not set the image tag back to an older version. Vault does not
support downgrades on raft data. Instead, redeploy the old version and restore the snapshot:
`v operator raft snapshot restore -force <file>`.

#### Notes from the 1.20.4 → 2.2.2 upgrade (2026-11)

- The path was: bank-vaults sidecar v1.33.1 → v1.33.2, Vault 1.20.4 → 1.21.4 (the last
  community 1.21 release) → 2.2.2. No config changes were needed.
- Since 2.x the image runs as the non-root `vault` user. The raft data is owned by
  `100:1000` and the group can write it. The operator sets `fsGroup: 1000`, so this
  works. If you ever see `permission denied` on `/vault/file`, check those permissions.
- `disable_mlock: true` is set, so the IPC_LOCK changes in 2.0.x do not matter.
- Joining nodes may restart the `bank-vaults` sidecar once with
  `dial tcp 127.0.0.1:8200: connect: connection refused`. This is harmless: the
  sidecar starts before Vault is listening and succeeds on the retry.

### Recovering a corrupted raft node

Symptom: one pod is crash-looping and its `vault` container logs show a BoltDB panic,
for example
`panic: freepages: failed to get all reachable pages (page 254: multiple references ...)`.

While the other two nodes are healthy, rebuild the broken node from the leader
(this example uses `vault-1`):

```bash
v operator raft snapshot save /tmp/vault.snap          # backup first (see above)
v operator raft list-peers
v operator raft remove-peer vault-1                    # or the node ID from list-peers
kubectl -n vault delete pvc vault-raft-vault-1 --wait=false
kubectl -n vault delete pod vault-1
```

The StatefulSet creates a fresh PVC. The bank-vaults sidecar then unseals the node
and rejoins it to the leader, which sends it a snapshot. Run the health check
afterwards. A single `storage.raft: failed to get previous log ... log not found`
warning on the new node is expected while it catches up.

### Resizing raft volumes

Longhorn supports online expansion, so patch each PVC directly:

```bash
kubectl -n vault patch pvc vault-raft-vault-1 --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
```

Also update `volumeClaimTemplates` in `cr-raft.yaml`, so rebuilt nodes get the same size.
Kubernetes does not let the operator change the template on the existing
StatefulSet (`spec: Forbidden: updates to statefulset spec ...`), and while that error
persists the operator applies no other changes either. After pushing the change,
delete only the StatefulSet object. The pods and volumes keep running, and the
operator recreates the StatefulSet and takes over the existing pods without
restarting them:

```bash
kubectl -n vault delete sts vault --cascade=orphan
```
