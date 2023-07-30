# Database Cluster

The database setup is based on the [zalando-operator][1]. With one cluster for
all productive applications and one or multipe for test purposes.

The productive cluster is created as HA cluster with pg_bouncer but without a
standby database.

## Operator setup

### Backup

Use own Minio for Backup.

Create new Policy with the name `SpiloS3Access`
and the poliy configuration:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::postgres-backups"
                "arn:aws:s3:::postgres-backups/*"
            ]
        }
    ]
}
```


Create new identity with `postgres-pod-role` with password and assign the
previously created policy.
Store both in the Vault under `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`


## Setup Cluster

Setup Cluster with own S3 Buckets, like Minio, requires some additional
configurations. Some leads can be found [here][2]





[1]: https://opensource.zalando.com/postgres-operator/
[2]: https://thedatabaseme.de/2022/03/26/backup-to-s3-configure-zalando-postgres-operator-backup-with-wal-g/

