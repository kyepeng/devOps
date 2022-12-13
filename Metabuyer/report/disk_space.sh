#! /bin/bash
set -e

if [ ! -f .env ]; then
   echo ".env file not file";
   exit 1
fi

export $(grep -v '^#' .env | xargs)

DATE=$(date '+%Y-%m-%d-%H%M%S')

sshpass -p $PASSWORD ssh genpitadmin@$SERVER_IP "df -Th | sed -n '1,10p'" >> ${DATE}_Server_Disk_Space.txt

sshpass -p $PASSWORD ssh genpitadmin@$SERVER_IP "sshpass -p ${PASSWORD} ssh genpitadmin@${SERVER_IP2} df -Th" >> ${DATE}_Database_Disk_Space.txt


az storage blob upload \
    --account-key ${AZURE_BLOB_ACCOUNT_KEY} \
    --account-name ${AZURE_BLOB_ACCOUNT_NAME} \
    --container-name "${AZURE_BLOB_CONTAINER_NAME}/DiskSpaceReport" \
    --file ${DATE}_Server_Disk_Space.txt \
    --name ${DATE}_Server_Disk_Space.txt \

az storage blob upload \
    --account-key ${AZURE_BLOB_ACCOUNT_KEY} \
    --account-name ${AZURE_BLOB_ACCOUNT_NAME} \
    --container-name "${AZURE_BLOB_CONTAINER_NAME}/DiskSpaceReport" \
    --file ${DATE}_Database_Disk_Space.txt \
    --name ${DATE}_Database_Disk_Space.txt \