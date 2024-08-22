# Set the base image to MySQL 8.3.0, which uses microdnf
FROM mysql:8.3.0

# Install additional required packages
USER root
RUN microdnf update && \
    microdnf install -y \
    python3-pip \
    less \
    mailcap \
    curl \
    gnupg \
    gzip \
    git \
    go && \
    pip3 install --upgrade awscli s3cmd python-magic awscli-plugin-endpoint && \
    microdnf clean all

# Set Default Environment Variables
ENV BACKUP_CREATE_DATABASE_STATEMENT=false \
    TARGET_DATABASE_PORT=3306 \
    CLOUD_SDK_VERSION=367.0.0 \
    # Release commit for https://github.com/FiloSottile/age
    AGE_VERSION=552aa0a07de0b42c16126d3107bd8895184a69e7 \
    AWS_REGION="nl-ams"

# Install FiloSottile/age for encryption, adjusting for the go environment
RUN git clone https://github.com/FiloSottile/age.git /tmp/age && \
    cd /tmp/age && \
    git checkout $AGE_VERSION && \
    go build -o . ./cmd/age && \
    cp age /usr/local/bin/ && \
    rm -rf /tmp/age

# Copy Scaleway configuration files from build context to the container
COPY ./scaleway/config /root/.aws/config

# Assume you have a backup script that uses mysqldump, awscli, etc.
COPY resources/perform-backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/perform-backup.sh

# Set the entrypoint to execute the backup script
CMD ["/usr/local/bin/perform-backup.sh"]
