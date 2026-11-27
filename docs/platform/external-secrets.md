# External Secrets

After some hickups with the *vault-secrets-webhook* I want to give
[*external secrets*][es] a try. With the webhook I had issues with the env variables
as not all Helm Charts made it so easy to use like the
*kube-monitoring-stack*: Grafana was using some complicated mapping setup which
made it necessary to use Secrets and `secret-refs`. And thats where my issues
started because the *vault-secrets-webhook* did not reliably replace the
placeholders ....

## Install Operator

I created a new Helm Chart App for [external secrets](https://github.com/mikevader/k3s-cluster-infra-apps/tree/master/cluster-platform/external-secrets)

``` yaml title="Chart.yaml"
apiVersion: v2
name: external-secrets
version: 0.0.0
dependencies:
  - name: external-secrets
    version: 0.5.9
    repository: https://charts.external-secrets.io
```

``` yaml title="values.yaml"
external-secrets:
  serviceMonitor:
    enabled: true
```

That will create the very basic setup for External Secrets.

## Setup Store

The store is the connection to Vault. There are two kinds:

- **ClusterSecretStore `vault-backend`**
  (`cluster-platform-apps/external-secrets/templates/secret-store.yaml`) for production
  apps. It logs in with Vault role `externalsecrets` (policy `framsburg_read`: read-only on
  `secret/framsburg/*`). Its `conditions` refuse namespaces labelled `client=cluster-test`.
- **SecretStore `vault`** in every `cluster-test` namespace, rendered by
  `apps-root-config/applications` (`enableVaultSecretStore`, see
  [App-of-apps groups](../cluster-core/app-groups.md)). It logs in with the namespace's
  ServiceAccount `vault-reader` and Vault role `test-namespace`, which only accepts
  namespaces labelled `client=cluster-test`. Vault needs `get namespaces` for that check
  (ClusterRole `vault-namespace-reader`).

Policies and roles are defined in `externalConfig` of
`cluster-platform-apps/vault/templates/cr-raft.yaml`.

!!! warning "Removed roles and policies stay in Vault"
    The bank-vaults configurer creates and updates roles and policies, but never deletes
    them. After removing one from `cr-raft.yaml`, delete it by hand:
    `vault delete auth/kubernetes/role/<name>` or `vault policy delete <name>`.

## Use/Create external secret

Last step: create a secret over the external secrets operator. Because the store
is clusterwide available, the only missing part is the `ExternalSecret`
definition.

As an example, the following is the OIDC client id and secret for grafana (a production
app). A `cluster-test` app uses `secretStoreRef: { kind: SecretStore, name: vault }`
instead. I
stored all the authentik OIDC clients in the vault. The external secret
manifest resides in the templates folder of the monitoring stack.

``` yaml title="templates/grafana-oidc-secret.yaml" linenums="1"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-oidc-secret
  namespace: monitoring-stack
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend # (1)
    kind: ClusterSecretStore
    namespace: external-secrets
  target:
    name: grafana-oidc-secret
    template:
      metadata:
        labels:
          app.kubernetes.io/part-of: monitoring-stack
      data:
        - secretKey: oidc-id
          remoteRef:
            key: secret/data/framsburg/grafana/oidc # (2)
            property: client-id # (3)
        - secretKey: oidc-secret
          remoteRef:
            key: secret/data/framsburg/grafana/oidc
            property: client-secret
```
1.  Name of the configured Secret Store (Make sure the kind is in sync with your
    Secret Store)
2.  Path of the secret in Vault. `secret` is the name of the secret engine,
    `data` is part of the path although not visible in Vault ... some Hashicorp
    Vault shenanigan
3.  Key of the secret

The generated secret will look like this:

``` yaml title=""

```

## Secret layout in Vault

All workload secrets live in the KV v2 mount `secret` under `framsburg/`. Everything
outside `framsburg/` is personal and only readable with an OIDC login.

| Path | Who reads it | Store |
|---|---|---|
| `framsburg/<app>[/...]` | production apps (all of `framsburg/*`, read-only) | ClusterSecretStore `vault-backend` |
| `framsburg/test/<namespace>[/...]` | only that `cluster-test` namespace | SecretStore `vault` in the namespace |
| `framsburg/test/shared/<name>` | every `cluster-test` namespace | SecretStore `vault` in the namespace |

The `test_namespace_read` policy grants exactly the last two rows. A `cluster-test`
namespace called `shared` would read `framsburg/test/shared/` as its own folder; every test
namespace can read it anyway, so this gives it nothing extra.

### CNPG backups in cluster-test

`cluster-test` has its own MinIO user for CNPG backups, stored as
`framsburg/test/shared/cnpg-minio-access` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
Test clusters back up to `s3://cnpg/test/` (barman adds `<cluster>/` below it), and the
MinIO user is limited to that prefix. Production clusters keep using
`framsburg/cnpg/minio-access` and `s3://cnpg/backups/`.

```sh
cat > cnpg-test.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:GetBucketLocation"], "Resource": ["arn:aws:s3:::cnpg"] },
    { "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::cnpg"],
      "Condition": { "StringLike": { "s3:prefix": ["test", "test/*"] } } },
    { "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject",
                 "s3:GetObjectTagging", "s3:PutObjectTagging",
                 "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::cnpg/test/*"] }
  ]
}
EOF
mc admin policy create minio2 cnpg-test cnpg-test.json
mc admin user add minio2 cnpg-test "$(openssl rand -hex 24)"   # note the secret key
mc admin policy attach minio2 cnpg-test --user cnpg-test
vault kv put -mount=secret framsburg/test/shared/cnpg-minio-access \
  AWS_ACCESS_KEY_ID=cnpg-test AWS_SECRET_ACCESS_KEY=<secret key>
```

Moving a cluster to `s3://cnpg/test/` starts a new, empty archive: take a backup right after
the switch (`kubectl cnpg backup <cluster> -n <namespace> --method plugin
--plugin-name barman-cloud.cloudnative-pg.io`). The old backups stay under
`s3://cnpg/backups/<cluster>/` for restores and are no longer pruned by the retention policy.

## Moving secrets

`hack/vault-kv-mv.sh` moves, renames or copies KV v2 secrets and folders, for example when
an app moves into or out of `cluster-test`. It checks for conflicts before writing, verifies
every copy and never prints values. See `hack/vault-kv-mv.sh --help`.

```sh
hack/vault-kv-mv.sh -n --copy framsburg/paperless/ framsburg/test/paperless/   # preview
hack/vault-kv-mv.sh --copy framsburg/paperless/ framsburg/test/paperless/
```

## Reference

[es]: https://external-secrets.io/ 
