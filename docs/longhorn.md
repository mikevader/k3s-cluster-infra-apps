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
