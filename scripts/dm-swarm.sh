#!/usr/bin/env bash
source conf/global.conf

if [ "$ENV" = "remote" ]; then
    num=0;
    NODES="conf/nodes.conf"
    for node in `cat $NODES`; do
        num=$(($num+1))
        USER=$(echo $node|awk -F@ '{print $1}')
        IP=$(echo $node|awk -F@ '{print $2}')
        echo $num-$USER-$IP
        ssh-copy-id $node
        docker-machine -D create --driver generic --generic-ip-address $IP --generic-ssh-user $USER swarm-$num
    done 
else
    for i in `seq $NODE_COUNT`; do
        docker-machine create -d virtualbox swarm-$i
    done
fi

eval $(docker-machine env swarm-$INIT_SWAM_NODE_NUM)

docker swarm init \
  --advertise-addr $(docker-machine ip swarm-$INIT_SWAM_NODE_NUM)

#manager节点
TOKEN=$(docker swarm join-token -q manager)

OLD_IFS="$IFS"
IFS=","
manager_nodes=($MANAGER_NODES_NUM)
IFS="$OLD_IFS"
for i in ${manager_nodes[@]}; do
     if [ "$i" -ne "$INIT_SWAM_NODE_NUM" ]; then 
        eval $(docker-machine env swarm-$i)

        docker swarm join \
            --token $TOKEN \
            --advertise-addr $(docker-machine ip swarm-$i) \
            $(docker-machine ip swarm-1):2377
    else 
        echo $i" is init node num" 
    fi     #ifend
done

#worker节点
eval $(docker-machine env swarm-$INIT_SWAM_NODE_NUM)
TOKEN=$(docker swarm join-token -q worker)

OLD_IFS="$IFS"
IFS=","
worker_nodes=($WOKER_NODES_NUM)
IFS="$OLD_IFS"
for i in ${worker_nodes[@]}; do
    eval $(docker-machine env swarm-$i)

    docker swarm join \
        --token $TOKEN \
        --advertise-addr $(docker-machine ip swarm-$i) \
        $(docker-machine ip swarm-1):2377
done

#ELK节点
OLD_IFS="$IFS"
IFS=","
elk_nodes=($ELK_NODES_NUM)
IFS="$OLD_IFS"
for i in ${elk_nodes[@]}; do
    eval $(docker-machine env swarm-$i)

    docker node update \
        --label-add elk=yes \
        swarm-$i
done

eval $(docker-machine env swarm-$INIT_SWAM_NODE_NUM)

echo ">> The swarm cluster is up and running"