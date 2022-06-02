#! /bin/bash
. ~/.nvm/nvm.sh

nvmVersion=`cut -d "=" -f2 <<< "$2"`;
if [ -z "$nvmVersion" ] 
    then 
        nvmVersion=10
fi


help() {
   # Display Help
   echo "Metabuyer environment start setup"
   echo
   echo "Syntax: bash start.sh [options] -nvm={nodeVersion}"
   echo "options:"
   echo "-a|-all           Run all except minion"
   echo "-b|-basic         Basic setup (Dockers containers, Establish connection)"
   echo "-c|-containers    Initialize containers"
   echo "-n|-nginx         Initialize NGIX containers"
   echo "-e|-establish     Establish connection"
   echo "-q|-queue         Stop queue"
   echo "-l|-local         Serve local"
   echo "-m|-minion        Serve minion"
}

initializeContainers() {
    echo "--------------------Initializing Containers-------------------";
    for container in 'redis' 'mongo' 'mysql' 'anubis' 'synergy' 'approval' 'bifrost'
    do
        if [ "$( docker container inspect -f '{{.State.Status}}' $container )" != "running" ]; 
        then
            docker start "$container";
        else
            echo "$container is up";            
        fi
    done
}

initializeNgixContainers() {
    echo "--------------------Initializing NGIX Containers-------------------";
    for container in 'nginx-approval' 'nginx-bifrost' 'nginx-synergy'
    do
        if [ "$( docker container inspect -f '{{.State.Status}}' $container )" != "running" ]; 
        then
            docker start "$container";
            sleep 1;
        else
            echo "$container is up";
        fi
    done
    sleep 3;
}

establishConnection() {
    echo "--------------------Establishing Connection---------------------";
    docker exec synergy php artisan me:es anubis;
    docker exec synergy php artisan me:es approval-engine;
    docker exec synergy php artisan me:es bifrost --secret=secret -f
    # check if able to establish the bifrost connection, if failed regenerate the key and rerun
    while :
    do
        bifrost_establish_connection=`docker exec synergy php artisan me:es bifrost --secret=secret -f`;
        if [[ ! "$bifrost_establish_connection" =~ .*"Credentials and Token regenerated in Bifrost successfully".* ]]
        then
            docker exec bifrost php artisan key:generate;
            docker exec synergy php artisan me:es bifrost --secret=secret -f;
        else
            break;
        fi
    done
}

stopQueue() {
    echo "--------------------Stop queue in bifrost--------------------";
    docker exec bifrost sudo supervisorctl "stop all";

    echo "--------------------Stop queue in synergy--------------------";
    docker exec synergy sudo supervisorctl "stop all";         
}

startQueue() {
    echo "--------------------Start queue in bifrost--------------------";
    docker exec bifrost sudo supervisorctl "start all";

    echo "--------------------Start queue in synergy--------------------";
    docker exec synergy sudo supervisorctl "start all";         
}

serveLocal() {
    echo "--------------------Serving local--------------------";
    cd metabuyer/synergy/angular;
    nvm use $nvmVersion;
    gulp serve;
}

serveMinion() {
    echo "--------------------Serving local--------------------";
    cd metabuyer/minion;
    nvm use $nvmVersion;
    nodemon app.js;
} 

case "$1" in
    -h|-help)
        help
        exit;;
    ""|-a|-all)
        initializeContainers
        initializeNgixContainers
        establishConnection
        stopQueue
        serveLocal;;
    -b|-basic)
        initializeContainers
        initializeNgixContainers
        establishConnection;;
    -c|-containers)
        initializeContainers;;
    -n|-nginx)
        initializeNgixContainers;;
    -e|-establish)
        establishConnection;;
    -q|-queue)
        stopQueue;;
    -l|-local)
        serveLocal;;
    -m|-minion)
        serveMinion;;
esac
