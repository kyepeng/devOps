# exit when any command fails
set -e

DIR="$(pwd)"
if [ ! -f $DIR/.restore_mongo_env ]; then
    echo "$(tput setaf 1)Error: .restore_mongo_env file NOT Found. $(tput sgr0)"
    exit 1
fi

## get variable from restore_mongo_env
export $(egrep -v '^#' $DIR/.restore_mongo_env | xargs)

if [[ -z $1 ]]; 
then
    date=$(date -d "2 days ago" '+%Y-%m-%d');
else
    date=$2;    
fi

## Make directory if not exist and enter 
mkdir -p ${FOLDER} && cd ${FOLDER};

## Declare all path and file name
bashPath=${AZURE_BLOB_CONTAINER_NAME}/GenpProd/mongo
auditData=Audit
dataWithoutAudit=DB
notificationData=Notification
tinyData=Tiny

## Audit Data
echo "Downloading auditData backup file from Azure..."
path=$bashPath/$AUDIT_DATA
file=GenpProd-$auditData-${date}.tar.bz2
echo $file
az storage blob download \
-f $file \
-c $path \
-n $file \
--account-key ${AZURE_BLOB_ACCOUNT_KEY} \
--account-name ${AZURE_BLOB_ACCOUNT_NAME} \
##

## Data Without Audit Data
printf "\n"
echo "Downloading dataWithoutAudit backup file from Azure..."
path=$bashPath/$DATA_WITHOUT_AUDIT
file=GenpProd-$dataWithoutAudit-${date}.tar.bz2
echo $file
az storage blob download \
-f $file \
-c $path \
-n $file \
--account-key ${AZURE_BLOB_ACCOUNT_KEY} \
--account-name ${AZURE_BLOB_ACCOUNT_NAME} \
##

## Notification Data
printf "\n"
echo "Downloading notificationData backup file from Azure..."
path=$bashPath/$NOTIFICATION_DATA
file=GenpProd-$notificationData-${date}.tar.bz2
echo $file
az storage blob download \
-f $file \
-c $path \
-n $file \
--account-key ${AZURE_BLOB_ACCOUNT_KEY} \
--account-name ${AZURE_BLOB_ACCOUNT_NAME} \
##

## Tiny Data
# printf "\n"
# echo "Downloading Tiny backup file from Azure..."
# path=$bashPath/$TINY_DATA
# file=GenpProd-$tinyData-${date}.tar.bz2
# echo $file
# az storage blob download \
# -f $file \
# -c $path \
# -n $file \
# --account-key ${AZURE_BLOB_ACCOUNT_KEY} \
# --account-name ${AZURE_BLOB_ACCOUNT_NAME} \
##

## Restore Mongo
DB_NAME=$MONGO_DATABASE;

printf "\n"
echo "Extracting Backup file(s)..."
rm -rf ${MONGO_BACKUP_FOLDER}
for file_name in *.tar.bz2;
do
    echo $file_name
    echo "Extracting ${file_name}..."
    pv ${file_name} | tar -xjf -;
done

printf "\n"
echo "Removing all collection from ${DB_NAME} except integrations..."
mongo ${DB_NAME} \
--host ${MONGO_HOST} \
--port ${MONGO_PORT} \
${DB_USERNAME:+-u "$MONGO_USERNAME"} \
${DB_PASSWORD:+-p "$MONGO_PASSWORD"} \
${DB_AUTH_DATABASE:+--authenticationDatabase="$MONGO_AUTH_DATABASE"} \
--quiet \
--eval 'db.getCollectionNames().forEach(function (c) { if (c !== "system.indexes" && c !== "integrations") { db.getCollection(c).drop() }})' \

printf "\n"
echo "Restoring Database..."
mongorestore \
    --host ${MONGO_HOST} \
    --port ${MONGO_PORT} \
    -d ${DB_NAME} \
    ${MONGO_BACKUP_FOLDER}/ \
    ${DB_USERNAME:+-u "$MONGO_USERNAME"} \
    ${DB_PASSWORD:+-p "$MONGO_PASSWORD"} \
    ${DB_AUTH_DATABASE:+--authenticationDatabase="$MONGO_AUTH_DATABASE"} \
    --gzip \
    --drop \
##

## Remove Folder
printf "\n"
echo "Removing downloaded folder..."
cd .. && rm -rf $FOLDER;
##

## Message 
printf "\n"
echo "Successfully restored the database"
##

# TODO: Add establish connection: bifrost, approval, minion
# TODO: Separate restore to multiple files
# TODO: Check why restore same collection 2 times
# db.integrations.find().forEach(function(d){ db.getSiblingDB('metabuyer_genp_staging')['integrations'].insert(d); });

