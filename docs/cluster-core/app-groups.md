# App-of-apps groups and guardrails

Every Argo CD application belongs to a **group** (an app of apps). The chart
`apps-root-config/applications` renders one group from its group file
`apps-root-config/applications/cluster-*.yaml`, layered on top of the chart defaults in
`apps-root-config/applications/values.yaml`. For each application the chart renders:

- the Argo CD `Application` (source path `<subFolder>/<app>`),
- its `Namespace`, with Pod Security Admission labels and the group's namespace labels,
- the optional **guardrails** below, inside that namespace,
- one `AppProject` per group, named after the group.

Parent apps live in the `default` project. The guardrails are owned by the parent, not by
the application, so an application can't remove or loosen them.

## Guardrails

Each guardrail is switched on per group and configured in `values.yaml`, where every key is
commented.

| Switch (group file) | Renders | Setting |
|---|---|---|
| `allowAllNamespaces: false` | `AppProject` destinations limited to the group's namespaces | — |
| `enableDefaultLimitRange` | LimitRange `core-resource-limits` | `limitRange` |
| `enableDefaultResourceQuota` | ResourceQuota `core-resource-quota` | `resourceQuota` |
| `enableDefaultNetworkPolicy` | NetworkPolicies `allow-from-k3s-ingress`, `allow-same-namespace`, `deny-by-default`, `allow-extra-ingress`, `restrict-egress` | `networkPolicy` |
| `enableVaultSecretStore` | ServiceAccount `vault-reader` + SecretStore `vault` | `vaultSecretStore` |
| `clusterResourceWhitelist` | cluster-scoped kinds the project may sync (by `name` if possible) | — |
| `namespaceResourceBlacklist` | namespaced kinds the project may not sync | — |

### Per-application overrides

`limitRange`, `resourceQuota`, `networkPolicy` and `vaultSecretStore` can be set per
application. The application's value is **overlaid** on the group's (helper
`apps.appSetting` in `templates/_helper.tpl`):

- maps merge key by key, so you only list the keys you change;
- lists and scalars replace the group's value: an application `limitRange.limits` replaces
  the whole list;
- `false`, `0` and empty values from the application win, unlike Helm's `mergeOverwrite`.

```yaml
applications:
  openclaw:
    resourceQuota:
      hard:
        requests.storage: 50Gi    # the other quota keys stay as in the group
```

## cluster-test

`cluster-test` is for apps that are tried out. It switches on every guardrail, so a test
app can't take resources, network access or secrets from the rest of the cluster:

- **Namespaces:** deploys only to its own applications' namespaces. Namespaces are labelled
  `client: cluster-test`, which Vault and External Secrets use to recognise test namespaces.
- **Resources:** a LimitRange sets defaults for containers without resources (the quota
  rejects pods without requests and limits). The quota limits CPU, memory, storage, PVCs and
  pods, and forbids `LoadBalancer` and `NodePort` services, so test apps can't take MetalLB
  IPs or node ports.
- **Network:** inbound only from the same namespace and the ingress controllers. Outbound
  only to the same namespace, cluster DNS and the internet; the pod and service CIDRs and the
  LAN are excluded.
- **Secrets:** only through the namespace's SecretStore `vault`, see
  [External Secrets](../platform/external-secrets.md#secret-layout-in-vault). The
  ClusterSecretStore `vault-backend` refuses test namespaces.
- **Cluster resources:** only what is whitelisted by name. Argo CD syncs as cluster-admin,
  so a whitelisted ClusterRoleBinding can still bind any ClusterRole; review those.
- **Blacklisted:** ResourceQuota, LimitRange, NetworkPolicy, SecretStore and ESO generators,
  so an app can't loosen its own guardrails or reach Vault around its SecretStore.
- **Removal:** `onRemoval: delete`; removing an app deletes it right away.

### Adding an app to cluster-test

1. Put the manifests in `cluster-test/<app>/` and add `<app>: {}` under `applications`.
2. Render the app and check it fits the limits. Raise them per application, with a
   comment explaining why (see the existing apps).
3. Secrets go to `secret/framsburg/test/<app>/...` and use
   `secretStoreRef: { kind: SecretStore, name: vault }`.
4. Allow extra traffic per application with `networkPolicy.extraIngress` and
   `networkPolicy.extraEgress`, for example the CNPG operator or the MinIO backup target.
5. Cluster-scoped resources the app needs go into `clusterResourceWhitelist`, by name.

!!! warning "NetworkPolicies see the API server on the node IPs"
    k3s (kube-router) evaluates policies after DNAT. An egress rule to the Kubernetes
    API must allow the control-plane node IPs on port 6443, not only the service IP
    `10.43.0.1`. The group file provides this rule as the YAML anchor
    `*egressKubeApiRule`.

!!! note "Moving an app between groups"
    See [Argo CD → Add app to app of apps](argocd.md#add-app-to-app-of-apps). Moving an app
    into `cluster-test` also moves its secrets: copy them to `framsburg/test/<app>/` first
    (`hack/vault-kv-mv.sh --copy`).
