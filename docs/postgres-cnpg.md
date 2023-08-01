# Postgres Cluster on CloudNative PG

[CouldNative PG](https://cloudnative-pg.io) is a opensourced operator from
[Enterprise DB](https://www.enterprisedb.com) one of the main contributers of
PostgreSQL.


## Base Setup

[Helm Chart](https://github.com/cloudnative-pg/charts/tree/main/charts/cloudnative-pg)


## Backup

Similar as Zalando


## Reload

To force restart/reload of secrets and configmaps in already created cluster,
the two either require the label `cnpg.io/reload` or must be reloaded manually.

```yaml title="example with external secret"
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cnpg-minio-access
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: cnpg-minio-access
    template:
      metadata:
        labels:
          "cnpg.io/reload": "true"
  data:

```

```bash
kubectl cnpg reload
```


## Monitoring



