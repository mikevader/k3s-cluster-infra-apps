# Monitoring with Prometheus Stack





## Part Two: OIDC Integration

This part should follow after [Vault] and [Authentik] are up and running.

### Create Application in Authentik

Create a new OIDC provider in authentik with _Redirect URIs/Origin_ pointing to [https://grafana.framsburg.ch]

Afterwards create a new application which uses the before created provider. Don't forget to create bindings
for uses or groups. You will need the following three informations out of authentik in the next steps.

* OpenID Configuration Issuer
* Client ID
* Client Secret


### Add secrets to vault

To use the vault CLI use the folling command:

```bash
$ kubectl exec -it vault-0 -n vault -- /bin/sh
```

Add the _Client ID_ and the _Client Secret_ as values to the vault:

Create the secrets with:

```bash
$ vault kv put kv-v2/framsburg/grafana/oidc client-id="someID" client-secret="someSecret"
```

Create a policy to access the secrets:
```bash
$ vault policy write grafana-app - <<EOF
path "kv-v2/data/framsburg/grafana/*" {
  capabilities = ["read", "list"]
}
EOF
```

!!! note

    Please be aware of the added `/data/`. This is not a typo but something the Vault expects when referencing
    this secret. It is not displayed in the UI either.


And as last step create a role which maps the k8s service account with the policy:

```bash
$ vault write auth/kubernetes/role/grafana-app \
    bound_service_account_names=monitoring-stack-grafana \
    bound_service_account_namespaces=monitoring-stack \
    policies=grafana-app \
    ttl=20m
```

### Secret Class

Create a SecretProviderClass in the templates

```yaml title="cluster-critical/monitoring-stack/templates/spc.yaml"
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-grafana
spec:
  provider: vault
  parameters:
    vaultAddress: "http://vault.vault:8200"
    roleName: "grafana-app"
    objects: |
      - objectName: "oidc-id"
        secretPath: "kv-v2/data/framsburg/grafana/oidc"
        secretKey: "client-id"
      - objectName: "oidc-secret"
        secretPath: "kv-v2/data/framsburg/grafana/oidc"
        secretKey: "client-secret"
  secretObjects:
    - data:
        - key: clientId
          objectName: oidc-id
        - key: clientSecret
          objectName: oidc-secret
      secretName: oidc
      type: Opaque
```

### Add Volumes in a Chart

The Grafana-Chart doesn't allow CSI volumes to be added to the normal volume
list. But it has a special value `extraSecretMount` for those volumes which
thankfully even combines the volume and mount entry into one.

```yaml title="cluster-critical/monitoring-stack/values.yaml"
kube-prometheus-stack:
  grafana:
...
    extraSecretMounts:
      - name: 'secrets-store-inline'
        mountPath: '/mnt/secrets-store'
        readOnly: true
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: vault-grafana
```

### Set environment variables incl secrets

```yaml title="cluster-critical/monitoring-stack/values.yaml"
kube-prometheus-stack:
  grafana:
...
    env:
      GF_AUTH_GENERIC_OAUTH_ENABLED: "true"
      GF_AUTH_GENERIC_OAUTH_NAME: "authentik"
      GF_AUTH_GENERIC_OAUTH_SCOPES: "openid profile email"
      GF_AUTH_GENERIC_OAUTH_AUTH_URL: "https://authentik.framsburg.ch/application/o/authorize/"
      GF_AUTH_GENERIC_OAUTH_TOKEN_URL: "https://authentik.framsburg.ch/application/o/token/"
      GF_AUTH_GENERIC_OAUTH_API_URL: "https://authentik.framsburg.ch/application/o/userinfo/"
      GF_AUTH_SIGNOUT_REDIRECT_URL: "https://authentik.framsburg.ch/application/o/grafana/end-session/"
      # Optionally enable auto-login (bypasses Grafana login screen)
      # GF_AUTH_OAUTH_AUTO_LOGIN: "true"
      # Optionally map user groups to Grafana roles
      # GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH: "contains(groups[*], 'Grafana Admins') && 'Admin' || contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'"

    envValueFrom:
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID:
        secretKeyRef:
          name: oidc
          key: clientId

      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET:
        secretKeyRef:
          name: oidc
          key: clientSecret
```


## Loki

Opnsense is a very interessting source for logs, but two steps are necessary.
The syslog source has to be configures for opnsense to forward the syslog
entries[7]. The second step is to parse the syslog entries and turn them into
sensible logfmt messages with labels[4][6].

You can add as a bonus the geoip.


## Custom Dashboard

https://www.mostlychris.com/keeping-tabs-on-your-network/

## Loki k8s events

* https://medium.com/@lysetskyyv/collecting-and-visualizing-kubernetes-events-with-loki-and-kubernetes-event-exporter-8f764b78185c
* https://github.com/resmoio/kubernetes-event-exporter
* https://grafana.com/docs/agent/latest/flow/reference/components/loki.source.kubernetes_events/
* 

## References

[1]: https://medium.com/aeturnuminc/monitoring-stack-deployment-to-a-kubernetes-cluster-prometheus-grafana-alertmanager-loki-dcc7339d4f19
[2]: https://grafana.com/docs/loki/latest/clients/promtail/configuration/#relabel_configs
[3]: https://akyriako.medium.com/linux-logging-with-grafana-loki-custom-promtail-labels-from-openstack-or-aws-ec2-metadata-436625cb644c
[4]: https://github.com/opnsense/core/issues/4911
[5]: https://grafana.com/grafana/dashboards/17547-opnsense-ids-ips/
[6]: https://github.com/onedr0p/home-ops/blob/61c672be2fa7c3cbb97eac523495affef5c6af07/cluster/apps/monitoring/vector/aggregator/filterlog-regex.txt
[7]: https://alexandre.deverteuil.net/post/syslog-relay-for-loki/


