# Harware Setup of Raspberry PIs

The initial setup is done with Ansible.

## Setup Minio Bucket for Backup

```bash title="Create minio bucket"
$ mc mb myminio/k3s
$ mc mb myminio/k3s/etcd-snapshot
```

```bash title="Create user with policy"
$ mc admin user add myminio k3s k3sk3sk3s

$ cat > /tmp/etcd-backups-policy.json <<EOF
{
  "Version": "2012-10-17",
      "Statement": [
    {
      "Action": [
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:ListAllMyBuckets",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::k3s"
      ],
      "Sid": ""
    },
    {
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::k3s/*"
      ],
      "Sid": ""
    }
  ]
}
EOF

$ mc admin policy add myminio etcd-backups-policy /tmp/etcd-backups-policy.json

$ mc admin policy set myminio etcd-backups-policy user=k3s
```


## Define K3S backup target

```Ansible title="k3s-server.services"
[Service]
ExecStart={{ k3s_binary_path }}/k3s server \
...
{% if backup_s3_enabled %}
    --etcd-s3 \
    --etcd-snapshot-schedule-cron='{{ backup_schedule_cron }}' \
    --etcd-s3-endpoint='{{ backup_s3_endpoint }}' \
    --etcd-s3-endpoint-ca='{{ systemd_dir }}/k3s-server.service.crt' \
    --etcd-s3-bucket='{{ backup_s3_bucket }}' \
    --etcd-s3-folder='{{ backup_s3_folder }}' \
    --etcd-s3-access-key='{{ backup_s3_access_key }}' \
    --etcd-s3-secret-key='{{ backup_s3_secret_key }}' \
{% endif %}
```

Define in ansible vault `ansible-vault edit group_vars/all.yaml` the four coordinates:
```properties title="vault"
backup_s3_access_key: k3s
backup_s3_secret_key: k3sk3sk3s
```

```properties title="hosts"
backup_schedule_cron: '0 */6 * * *'
backup_s3_bucket: k3s
backup_s3_folder: etcd-snapshot
backup_s3_endpoint_ca: |
          -----BEGIN CERTIFICATE-----
          MIIDgTCCAmmgAwIBAgIJAJ85e+K5ngFRMA0GCSqGSIb3DQEBCwUAMGsxCzAJBgNV
```



## (Optional) Rolling Update

The initial ansible script is not very suitable for rolling updates as it
assumes it is about to initialize a cluster which requires the order

1. First master node which initializes (or restores) the etcd state
2. All other master nodes which sync up to the first
3. All worker nodes

That is very efficient for setup and restore but would mean some outages if
applied on a live cluster. Therefore we need a playbook which goes through
every node sequentially (we have no special requirement on performance) and
cares about draining nodes correctly.

Ideally we can reuse roles from the cluster setup playbook.
