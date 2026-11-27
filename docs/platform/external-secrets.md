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

The next and most important part is the Secret Store. This is the actual
connection to the vault and has the vault coordinates as well as access keys.
To make it an easy setup, this is part of the external secrets application.

``` yaml title="templates/secret-store.yaml"
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "kubernetes"
      version: "v2"
      auth:
        # Authenticate against Vault using a Kubernetes ServiceAccount
        # token stored in a Secret.
        # https://www.vaultproject.io/docs/auth/kubernetes
        kubernetes:
          # Path where the Kubernetes authentication backend is mounted in Vault
          mountPath: "kubernetes"
          # A required field containing the Vault Role to assume.
          role: "externalSecret" # (1)
          # Optional service account field containing the name
          # of a kubernetes ServiceAccount
          serviceAccountRef:
            name: "external-secrets"
```

1.  This role name has to be created in the Vault or configured for the operator
    to create it.

## Use/Create external secret

Last step: create a secret over the external secrets operator. Because the store
is clusterwide available, the only missing part is the `ExternalSecret`
definition.

As an example, the following is the OIDC client id and secret for grafana. I
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
| `framsburg/<app>[/...]` | production groups (all of `framsburg/*`, read-only) | ClusterSecretStore `vault-backend` |
| `framsburg/test/<namespace>[/...]` | only that `cluster-test` namespace | SecretStore `vault` in the namespace |
| `framsburg/shared/<group>/<name>` | every app of one app-of-apps group | the group's store (above) |

`<group>` is the app-of-apps folder without `cluster-` and `-apps`: `critical`, `platform`,
`utility`, `media`, `rpg`, `test`.

Production groups can technically read every group's shared folder (`vault-backend` reads
all of `framsburg/*`); the split still keeps one credential per group, so it can be limited,
rotated or revoked without touching the other groups. For `cluster-test` it is enforced:
the `test_namespace_read` policy only adds `framsburg/shared/test/*`.

### Shared credentials: CNPG backups

Each group has its own MinIO user for CNPG backups, stored as
`framsburg/shared/<group>/cnpg-minio-access` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
A group's clusters back up to their own prefix, `s3://cnpg/<group>/` (barman adds
`<cluster>/` below it), so the MinIO user can be limited to that prefix:

```sh
group=test
cat > cnpg-$group.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:GetBucketLocation"], "Resource": ["arn:aws:s3:::cnpg"] },
    { "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::cnpg"],
      "Condition": { "StringLike": { "s3:prefix": ["$group", "$group/*"] } } },
    { "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject",
                 "s3:GetObjectTagging", "s3:PutObjectTagging",
                 "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::cnpg/$group/*"] }
  ]
}
EOF
mc admin policy create minio2 cnpg-$group cnpg-$group.json
mc admin user add minio2 cnpg-$group "$(openssl rand -hex 24)"   # note the secret key
mc admin policy attach minio2 cnpg-$group --user cnpg-$group
vault kv put -mount=secret framsburg/shared/$group/cnpg-minio-access \
  AWS_ACCESS_KEY_ID=cnpg-$group AWS_SECRET_ACCESS_KEY=<secret key>
```

Until a group has its own user, copy the existing credential (this grants the old, broad
access) with [`hack/vault-kv-mv.sh`](https://github.com/mikevader/k3s-cluster-infra-apps/blob/master/hack/vault-kv-mv.sh):

```sh
hack/vault-kv-mv.sh --copy framsburg/cnpg/minio-access framsburg/shared/<group>/cnpg-minio-access
```

Moving an existing cluster to `s3://cnpg/<group>/` starts a new, empty archive: take a
backup right after the switch (`kubectl cnpg backup <cluster> -n <namespace> --method plugin
--plugin-name barman-cloud.cloudnative-pg.io`). The old backups stay under
`s3://cnpg/backups/<cluster>/` for restores and are no longer pruned by the retention policy.

## Reference

[es]: https://external-secrets.io/ 
