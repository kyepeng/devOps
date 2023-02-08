#!/bin/bash

set -e

DIR="$(pwd)"
DATE=$(if ! date -v-1d +%Y-%m-%d 2>/dev/null; then date --date="-1 day" +%Y-%m-%d; fi)

## Read .env file
if [ ! -f $DIR/.env ]; then
    echo "$(tput setaf 1)Error: .env file NOT Found. Copying .env.example as .env... $(tput sgr0)"
    cp .env.example .env
    echo ".env file copied. Please update the .env file."
    exit 1
fi
export $(egrep -v '^#' $DIR/.env | xargs)
##


## Delete old backups
echo "Deleting existing backup files..."
if [ "$(find . -maxdepth 1 -type f | grep -i '.*\.sql$')" ]; then
    rm -f *.sql
fi
if [ "$(find . -maxdepth 1 -type f | grep -i '.*\.tar.bz2$')" ]; then
    rm -f *.tar.bz2
fi
rm -rf ${MONGO_BACKUP_FOLDER}
# ##

## Download Backup Files
echo "Downloading backup files..."
APPROVAL_BACKUP_S3_URI=$(echo ${APPROVAL_BACKUP_S3_URI} | sed "s|\${DATE}|${DATE}|g")
BIFROST_BACKUP_S3_URI=$(echo ${BIFROST_BACKUP_S3_URI} | sed "s|\${DATE}|${DATE}|g")
MONGO_BACKUP_S3_URI=$(echo ${MONGO_BACKUP_S3_URI} | sed "s|\${DATE}|${DATE}|g")

aws s3 cp ${APPROVAL_BACKUP_S3_URI} .
aws s3 cp ${BIFROST_BACKUP_S3_URI} .
aws s3 cp ${MONGO_BACKUP_S3_URI} .
##

APPROVAL_FILENAME=$(basename ${APPROVAL_BACKUP_S3_URI})
BIFROST_FILENAME=$(basename ${BIFROST_BACKUP_S3_URI})
MONGO_FILENAME=$(basename ${MONGO_BACKUP_S3_URI})

## Mongo
echo "Extracting Mongo backup..."
pv ${MONGO_FILENAME} | tar -xjf -

echo "Dropping metabuyer database..."
mongo \
	--host ${MONGO_HOST} \
	--port ${MONGO_PORT} \
	${MONGO_USERNAME:+-u "$MONGO_USERNAME"} \
    ${MONGO_PASSWORD:+-p "$MONGO_PASSWORD"} \
    ${MONGO_AUTH_DATABASE:+--authenticationDatabase="$MONGO_AUTH_DATABASE"} \
    ${MONGO_DATABASE} \
    --quiet \
    --eval 'db.dropDatabase()'

echo "Restoring Mongo backup..."
mongorestore \
	--host ${MONGO_HOST} \
	--port ${MONGO_PORT} \
	${MONGO_USERNAME:+-u "$MONGO_USERNAME"} \
    ${MONGO_PASSWORD:+-p "$MONGO_PASSWORD"} \
    ${MONGO_AUTH_DATABASE:+--authenticationDatabase="$MONGO_AUTH_DATABASE"} \
    -d ${MONGO_DATABASE} ${MONGO_BACKUP_FOLDER} \
    --numParallelCollections=${NUM_PARALLEL_COLLECTIONS} \
    --gzip

echo "Changing all user password to 'asdf'..."
mongo \
	--host ${MONGO_HOST} \
	--port ${MONGO_PORT} \
	${MONGO_USERNAME:+-u "$MONGO_USERNAME"} \
    ${MONGO_PASSWORD:+-p "$MONGO_PASSWORD"} \
    ${MONGO_AUTH_DATABASE:+--authenticationDatabase="$MONGO_AUTH_DATABASE"} \
    ${MONGO_DATABASE} \
    --quiet \
    --eval 'db.getCollection("users").update({}, {$set: {password: "$2y$10$wdBkkkHjdwWlpsbgQAaCoe0XrY/Lol/xp8hMYMBs4PZT/HFshSh.a"}}, {multi:true})'
##

## Approval
echo "Restoring Approval Engine..."
mysql \
	-h 127.0.0.1 \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
	--execute="DROP SCHEMA IF EXISTS ${MYSQL_APPROVAL_DATABASE}; CREATE SCHEMA ${MYSQL_APPROVAL_DATABASE};"

if [ "$(uname)" = "Darwin" ]
then
	sed -i "" "/^CREATE DATABASE /d" ${APPROVAL_FILENAME}
	sed -i "" "/^USE /d" ${APPROVAL_FILENAME}
else
	sed -i "/^CREATE DATABASE /d" ${APPROVAL_FILENAME}
	sed -i "/^USE /d" ${APPROVAL_FILENAME}
fi

mysql \
	-h ${MYSQL_HOST_IP} \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
	${MYSQL_APPROVAL_DATABASE} < ${APPROVAL_FILENAME}\

echo "Updating oauth_clients table..."
mysql \
	-h ${MYSQL_HOST_IP} \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
    --max-allowed-packet=1073741824 \
	${MYSQL_APPROVAL_DATABASE} << "EOF"
UPDATE oauth_clients set secret = "0ZhQdAmlnNgzJKHnqCItsgrQds9zQ7zvbZBQJ2oR";
EOF
##

## Bifrost
echo "Restoring Bifrost..."
mysql \
	-h ${MYSQL_HOST_IP} \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
	--max-allowed-packet=1073741824 \
	--execute="DROP SCHEMA IF EXISTS ${MYSQL_BIFROST_DATABASE}; CREATE SCHEMA ${MYSQL_BIFROST_DATABASE}"

if [ "$(uname)" = "Darwin" ]
then
	sed -i "" "/^CREATE DATABASE /d" ${BIFROST_FILENAME}
	sed -i "" "/^USE /d" ${BIFROST_FILENAME}
else
	sed -i "/^CREATE DATABASE /d" ${BIFROST_FILENAME}
	sed -i "/^USE /d" ${BIFROST_FILENAME}
fi

mysql \
	-h ${MYSQL_HOST_IP} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
	-u${MYSQL_USER} \
	${MYSQL_BIFROST_DATABASE} < ${BIFROST_FILENAME}

echo "Creating secret in Bifrost..."
mysql \
	-h ${MYSQL_HOST_IP} \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
    --max-allowed-packet=1073741824 \
	--execute="TRUNCATE ${MYSQL_BIFROST_DATABASE}.configurations;"

mysql \
	-h ${MYSQL_HOST_IP} \
	-u${MYSQL_USER} \
	${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
    --max-allowed-packet=1073741824 \
	${MYSQL_BIFROST_DATABASE} << "EOF"
INSERT INTO configurations
VALUES
	(1, "integration_secret", "{\"secret\": \"secret\"}", 1, 1, now(), now(), NULL, NULL);
EOF
##

echo "Clearing Redis..."
docker exec -it redis redis-cli flushdb

echo "Establishing connections..."
docker exec -it synergy php artisan me:es approval-engine
docker exec -it synergy php artisan me:es anubis
docker exec -it synergy php artisan me:es bifrost --secret=secret -f