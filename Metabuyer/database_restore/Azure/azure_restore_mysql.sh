# exit when any command fails
set -e

DIR="$(pwd)"
if [ ! -f $DIR/.restore_mysql_env ]; then
    echo "$(tput setaf 1)Error: .restore_mysql_env file NOT Found. $(tput sgr0)"
    exit 1
fi

## get variable from restore_mysql_env
export $(egrep -v '^#' $DIR/.restore_mysql_env | xargs)

## Download File
mkdir -p ${FOLDER} && cd ${FOLDER};
date=$(date -d "yesterday" '+%Y-%m-%d');

for database in "approval" "bifrost"
    do
        DB_NAME=MYSQL_${database^^}_DATABASE;
        path=${AZURE_BLOB_CONTAINER_NAME}/GenpProd/mysql/${database};
        file="GenpProd-${database^}-$date.sql";
        echo "Downloading database backup file...";
        mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "DROP DATABASE IF EXISTS ${!DB_NAME}" \

        az storage blob download \
        -f $file \
        -c $path \
        -n $file \
        --account-key ${AZURE_BLOB_ACCOUNT_KEY} \
        --account-name ${AZURE_BLOB_ACCOUNT_NAME} \

        ## Restore MySql
        echo "Create Database - ${!DB_NAME} if not exist...";
        mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${!DB_NAME}";\

        printf "\n"
        echo "Restoring Database..."
        mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --database=${!DB_NAME} < ${file}\
        ##
    done

## Remove Folder
printf "\n"
echo "Removing downloaded folder..."
cd .. && rm -rf $FOLDER;
##

## Message 
printf "\n"
echo "Successfully restored the database"
##
