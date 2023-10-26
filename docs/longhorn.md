# Longhorn


## Setup Minio for Backup

Use the minio cli `mc` which has an alias called `myminio`

```bash title="Create minio bucket"
$ mc mb myminio/k3sbackups
$ mc mb myminio/k3sbackups/longhorn
```

```bash title="Create user with policy"
$ mc admin user add myminio longhorn mypass
$ cat > /tmp/k3s-backups-policy.json <<EOF
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
        "arn:aws:s3:::k3sbackups"
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
        "arn:aws:s3:::k3sbackups/*"
      ],
      "Sid": ""
    }
  ]
}
EOF

$ mc admin policy add myminio k3s-backups-policy /tmp/k3s-backups-policy.json

$ mc admin policy set myminio k3s-backups-policy user=longhorn
```

## Define backup target in longhorn

```yaml title="longhorn values.yaml"
longhorn:
  defaultSettings:
    backupTarget: 's3://k3sbackups@us-east-1/longhorn'
    backupTargetCredentialSecret: minio-secret
...
```

## Copy from one Volume to another

```yaml title="copy-job.yaml"
apiVersion: batch/v1
kind: Job
metadata:
  namespace: default  # namespace where the PVC's exist
  name: volume-migration
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 3
  template:
    metadata:
      name: volume-migration
      labels:
        name: volume-migration
    spec:
      restartPolicy: Never
      containers:
        - name: volume-migration
          image: ubuntu:xenial
          tty: true
          command: [ "/bin/sh" ]
          args: [ "-c", "cp -r -v /mnt/old /mnt/new" ]
          volumeMounts:
            - name: old-vol
              mountPath: /mnt/old
            - name: new-vol
              mountPath: /mnt/new
      volumes:
        - name: old-vol
          persistentVolumeClaim:
            claimName: data-source-pvc # change to data source PVC
        - name: new-vol
          persistentVolumeClaim:
            claimName: data-target-pvc # change to data target PVC
```


