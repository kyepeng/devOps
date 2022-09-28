#!/bin/bash

# exit when any command fails
set -e

if [ ! -f .env ]; then
   echo ".env file not file";
   exit 1
fi

export $(grep -v '^#' .env | xargs)

COLLECTION=$1
QUERY=$2

DATE=$(date -d "yesterday" '+%Y-%m-%d')
YESTERDAY="$DATE"T00:00:00.000Z
TODAY=$(date '+%Y-%m-%d')T00:00:00.000Z
QUERY="{'created_at':{'$gte':ISODate('$YESTERDAY'),'$lt':ISODate('$TODAY')}}"

### Mongo export to csv
if [ ! -z $2 ]
    mongoexport --username $DB_USER --password $DB_PASSWORD --authenticationDatabase $AUTH_DB --host $DB_HOST --db $DB --port $DB_PORT --collection $COLLECTION --type=csv -o "$DATE-${COLLECTION}.csv" --fieldFile fields.txt --query $QUERY

then
    mongoexport --username $DB_USER --password $DB_PASSWORD --authenticationDatabase $AUTH_DB --host $DB_HOST --db $DB --port $DB_PORT --collection $COLLECTION --type=csv -o "$DATE-${COLLECTION}.csv" --fieldFile fields.txt --forceTableScan
fi
##

if [ -f $DATE-${COLLECTION}.csv ]; then

    ### Rename CSV Header
    HEADER=$(<header.txt)
    sed -i "1s/.*/${HEADER}/" $DATE-${COLLECTION}.csv
    ##

    ### Upload file to azure
        az storage blob upload \
        --account-key ${AZURE_BLOB_ACCOUNT_KEY} \
        --account-name ${AZURE_BLOB_ACCOUNT_NAME} \
        --container-name "${AZURE_BLOB_CONTAINER_NAME}/Mongo" \
        --file $DATE-${COLLECTION}.csv \
        --name $DATE-${COLLECTION}.csv; \
    ##

    ### Remove generated file
        rm -f $DATE-${COLLECTION}.csv
    ##

fi
