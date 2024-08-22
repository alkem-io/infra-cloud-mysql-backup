#!/bin/sh

# Set the has_failed variable to false. This will change if any of the subsequent database backups/uploads fail.
has_failed=false

# Configure AWS CLI for Scaleway S3
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile scaleway
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile scaleway
aws configure set region "$AWS_REGION" --profile scaleway  # Replace with your Scaleway region
aws configure set output "json" --profile scaleway

# Set the BACKUP_CREATE_DATABASE_STATEMENT variable
if [ "$BACKUP_CREATE_DATABASE_STATEMENT" = "true" ]; then
    BACKUP_CREATE_DATABASE_STATEMENT="--databases"
else
    BACKUP_CREATE_DATABASE_STATEMENT=""
fi

if [ "$TARGET_ALL_DATABASES" = "true" ]; then
    # Ignore any databases specified by TARGET_DATABASE_NAMES
    if [ ! -z "$TARGET_DATABASE_NAMES" ]; then
        echo "Both TARGET_ALL_DATABASES is set to 'true' and databases are manually specified by 'TARGET_DATABASE_NAMES'. Ignoring 'TARGET_DATABASE_NAMES'..."
        TARGET_DATABASE_NAMES=""
    fi
    # Build Database List
    ALL_DATABASES_EXCLUSION_LIST="'mysql','sys','tmp','information_schema','performance_schema'"
    ALL_DATABASES_SQLSTMT="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${ALL_DATABASES_EXCLUSION_LIST})"
    if ! ALL_DATABASES_DATABASE_LIST=$(mysql -u $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p$TARGET_DATABASE_PASSWORD -P $TARGET_DATABASE_PORT -ANe"${ALL_DATABASES_SQLSTMT}"); then
        echo -e "Building list of all databases failed at $(date +'%d-%m-%Y %H:%M:%S')." | tee -a /tmp/kubernetes-cloud-mysql-backup.log
        has_failed=true
    fi
    if [ "$has_failed" = false ]; then
        for DB in ${ALL_DATABASES_DATABASE_LIST}; do
            TARGET_DATABASE_NAMES="${TARGET_DATABASE_NAMES}${DB},"
        done
        # Remove trailing comma
        TARGET_DATABASE_NAMES=${TARGET_DATABASE_NAMES%?}
        echo -e "Successfully built list of all databases (${TARGET_DATABASE_NAMES}) at $(date +'%d-%m-%Y %H:%M:%S')."
    fi
fi

# Loop through all the defined databases, separating by a comma
if [ "$has_failed" = false ]; then
    for CURRENT_DATABASE in ${TARGET_DATABASE_NAMES//,/ }; do

        DUMP=$CURRENT_DATABASE$(date +$BACKUP_TIMESTAMP).sql
        # Perform the database backup. If successful, upload the backup to Scaleway S3. If unsuccessful, print an entry to the console and the log, and set has_failed to true.
        if sqloutput=$(mysqldump --default-auth=mysql_native_password --set-gtid-purged=OFF -u $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p$TARGET_DATABASE_PASSWORD -P $TARGET_DATABASE_PORT $BACKUP_ADDITIONAL_PARAMS $BACKUP_CREATE_DATABASE_STATEMENT $CURRENT_DATABASE 2>&1 >/tmp/$DUMP); then

            echo -e "Database backup successfully completed for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."

            # Convert BACKUP_COMPRESS to lowercase before executing if statement
            BACKUP_COMPRESS=$(echo "$BACKUP_COMPRESS" | awk '{print tolower($0)}')

            # If Backup Compress is true, compress the file to .gz format
            if [ "$BACKUP_COMPRESS" = "true" ]; then
                if [ -z "$BACKUP_COMPRESS_LEVEL" ]; then
                    BACKUP_COMPRESS_LEVEL="9"
                fi
                gzip -${BACKUP_COMPRESS_LEVEL} -c /tmp/"$DUMP" >/tmp/"$DUMP".gz
                rm /tmp/"$DUMP"
                DUMP="$DUMP".gz
            fi

            # Optionally encrypt the backup
            if [ -n "$AGE_PUBLIC_KEY" ]; then
                cat /tmp/"$DUMP" | age -a -r "$AGE_PUBLIC_KEY" >/tmp/"$DUMP".age
                echo -e "Encrypted backup with age"
                rm /tmp/"$DUMP"
                DUMP="$DUMP".age
            fi

            # Perform the upload to Scaleway S3-compatible storage using the Scaleway profile
            if awsoutput=$(aws --profile scaleway --endpoint-url=$AWS_S3_ENDPOINT s3 cp /tmp/$DUMP s3://$SCALEWAY_BUCKET_NAME$SCALEWAY_BUCKET_BACKUP_PATH/$DUMP 2>&1); then
                echo -e "Database backup successfully uploaded for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."
            else
                echo -e "Database backup failed to upload for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $awsoutput" | tee -a /tmp/kubernetes-cloud-mysql-backup.log
                has_failed=true
            fi
            rm /tmp/"$DUMP"

        else
            echo -e "Database backup FAILED for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $sqloutput" | tee -a /tmp/kubernetes-cloud-mysql-backup.log
            has_failed=true
        fi

    done
fi

# Check if any of the backups have failed. If so, exit with a status of 1. Otherwise, exit cleanly with a status of 0.
if [ "$has_failed" = true ]; then
    echo -e "kubernetes-cloud-mysql-backup encountered 1 or more errors. Exiting with status code 1."
    exit 1
fi
