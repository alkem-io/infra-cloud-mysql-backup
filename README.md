# kubernetes-cloud-mysql-backup

kubernetes-cloud-mysql-backup is a container image based on mysql:v8.3.0 container. This container is designed to run in Kubernetes as a cronjob to perform automatic backups of MySQL databases to Amazon S3. It was created to meet my requirements for regular and automatic database backups of MySQL cluster with MySQL v8.3.0. It has a relatively simple feature set for now.

Currently, kubernetes-cloud-mysql-backup supports the backing up of MySQL Databases. It can perform backups of multiple MySQL databases from a single database host. When triggered, a full database dump is performed using the `mysqldump` command for each configured database. The backup(s) are then uploaded to an Amazon S3 Bucket. 

Over time, kubernetes-cloud-mysql-backup will be updated to support more features and functionality.


## Environment Variables

The below table lists all of the Environment Variables that are configurable for kubernetes-cloud-mysql-backup.

| Environment Variable             | Purpose                                                                                                                                                                                                                                               |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BACKUP_CREATE_DATABASE_STATEMENT | **(Optional - default `false`)** Adds the `CREATE DATABASE` and `USE` statements to the MySQL backup by explicitly specifying the `--databases` flag (see [here](https://dev.mysql.com/doc/refman/5.7/en/mysqldump.html#option_mysqldump_databases)). |
| BACKUP_ADDITIONAL_PARAMS         | **(Optional)** Additional parameters to add to the `mysqldump` command.                                                                                                                                                                               |
| AWS_ACCESS_KEY_ID                | **(Required for AWS Backend)** AWS IAM Access Key ID.                                                                                                                                                                                                 |
| AWS_SECRET_ACCESS_KEY            | **(Required for AWS Backend)** AWS IAM Secret Access Key. Should have very limited IAM permissions (see below for example) and should be configured using a Secret in Kubernetes.                                                                     |
| AWS_DEFAULT_REGION               | **(Required for AWS Backend)** Region of the S3 Bucket (e.g. eu-west-2).                                                                                                                                                                              |
| AWS_BUCKET_NAME                  | **(Required for AWS Backend)** The name of the S3 bucket.                                                                                                                                                                                             |
| AWS_BUCKET_BACKUP_PATH           | **(Required for AWS Backend)** Path the backup file should be saved to in S3. E.g. `/database/myblog/backups`. **Do not put a trailing / or specify the filename.**                                                                                   |
| AWS_S3_ENDPOINT                  | **(Optional)** The S3-compatible storage endpoint (for MinIO/other cloud storage) bucket.                                                                                                                                                             |
| AWS_REGION                       | **(Optional)** The AWS region where the S3 bucket is created                                                                   |
**                                                                                  |
| TARGET_DATABASE_HOST             | **(Required)** Hostname or IP address of the MySQL Host.                                                                                                                                                                                              |
| TARGET_DATABASE_PORT             | **(Optional)** Port MySQL is listening on (Default: 3306).                                                                                                                                                                                            |
| TARGET_DATABASE_NAMES            | **(Required unless TARGET_ALL_DATABASES is true)** Name of the databases to dump. This should be comma seperated (e.g. `database1,database2`).                                                                                                        |
| TARGET_ALL_DATABASES             | **(Optional - default `false`)** Set to `true` to ignore `TARGET_DATABASE_NAMES` and dump all non-system databases.                                                                                                                                   |
| TARGET_DATABASE_USER             | **(Required)** Username to authenticate to the database with.                                                                                                                                                                                         |
| TARGET_DATABASE_PASSWORD         | **(Required)** Password to authenticate to the database with. Should be configured using a Secret in Kubernetes.                                                                                                                                      |
| BACKUP_TIMESTAMP                 | **(Optional)** Date string to append to the backup filename ([date](http://man7.org/linux/man-pages/man1/date.1.html) format). Leave unset if using S3 Versioning and date stamp is not required.                                                     |
| BACKUP_COMPRESS                  | **(Optional)** (true/false) Enable or disable gzip backup compression - (Default False).                                                                                                                                                              |
| BACKUP_COMPRESS_LEVEL            | **(Optional - default `9`)** Set the gzip level used for compression.                                                                                                                                                                                 |
| AGE_PUBLIC_KEY                   | **(Optional)** Public key used to encrypt backup with [FiloSottile/age](https://github.com/FiloSottile/age). Leave blank to disable backup encryption.                                                                                                |
                                                                                                                     |

## S3 Backend Configuration

The below subheadings detail how to configure kubernetes-cloud-mysql-backup to backup to an Amazon S3 backend.

### S3 - Configuring the S3 Bucket & AWS IAM User

By default, kubernetes-cloud-mysql-backup performs a backup to the same path, with the same filename each time it runs. It therefore assumes that you have Versioning enabled on your S3 Bucket. A typical setup would involve S3 Versioning, with a Lifecycle Policy.

If a timestamp is required on the backup file name, the BACKUP_TIMESTAMP Environment Variable can be set.

An IAM User should be created, with API Credentials. An example Policy to attach to the IAM User (for a minimal permissions set) is as follows:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::<BUCKET NAME>"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::<BUCKET NAME>/*"
        }
    ]
}
```


### S3 - Example Kubernetes Cronjob

An example of how to schedule this container in Kubernetes as a cronjob is below. This would configure a database backup to run each day at 01:00am. The AWS Secret Access Key, Target Database Password are stored in secrets.

```
apiVersion: v1
kind: Secret
metadata:
  name: my-database-backup
type: Opaque
data:
  aws_secret_access_key: <AWS Secret Access Key>
  database_password: <Your Database Password>
---
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: my-database-backup
spec:
  schedule: "0 01 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: my-database-backup
            image: ghcr.io/benjamin-maynard/kubernetes-cloud-mysql-backup:v2.6.0
            imagePullPolicy: Always
            env:
              - name: AWS_ACCESS_KEY_ID
                value: "<Your Access Key>"
              - name: AWS_SECRET_ACCESS_KEY
                valueFrom:
                   secretKeyRef:
                     name: my-database-backup
                     key: aws_secret_access_key
              - name: AWS_DEFAULT_REGION
                value: "<Your S3 Bucket Region>"
              - name: AWS_BUCKET_NAME
                value: "<Your S3 Bucket Name>"
              - name: AWS_BUCKET_BACKUP_PATH
                value: "<Your S3 Bucket Backup Path>"
              - name: TARGET_DATABASE_HOST
                value: "<Your Target Database Host>"
              - name: TARGET_DATABASE_PORT
                value: "<Your Target Database Port>"
              - name: TARGET_DATABASE_NAMES
                value: "<Your Target Database Name(s)>"
              - name: TARGET_DATABASE_USER
                value: "<Your Target Database Username>"
              - name: TARGET_DATABASE_PASSWORD
                valueFrom:
                   secretKeyRef:
                     name: my-database-backup
                     key: database_password
              - name: BACKUP_TIMESTAMP
                value: "_%Y_%m_%d"
          restartPolicy: Never
```