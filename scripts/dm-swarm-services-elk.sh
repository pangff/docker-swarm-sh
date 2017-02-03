#!/usr/bin/env bash

#docker service rm logstash elasticsearch proxy swarm-listener kibana
#docker network rm elk proxy
#docker service rm logstash redis proxy hello-service logspout kibana elasticsearch swarm-listener

docker network rm elk proxy
source conf/global.conf
echo "-------------------------"
echo "env:"$ENV"--NODE_COUNT:"$NODE_COUNT"--ELK_NODE_COUNT" $ELK_NODE_COUNT
echo "-------------------------"

eval $(docker-machine env swarm-1)

NODE_COUNT=$(docker node ls | grep -ic Active)
echo "NODE_COUNT-"$NODE_COUNT

docker network create --driver overlay --subnet=10.0.8.0/24 proxy
docker network create --driver overlay --subnet=10.0.9.0/24 elk

sleep 10

docker service create --name swarm-listener \
    --network proxy \
    --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
    -e DF_NOTIF_CREATE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/reconfigure \
    -e DF_NOTIF_REMOVE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/remove \
    --constraint 'node.role==manager' \
    vfarcic/docker-flow-swarm-listener

docker service create --name proxy \
    -p 80:80 \
    -p 443:443 \
    --network proxy \
    -e MODE=swarm \
    -e LISTENER_ADDRESS=swarm-listener \
    vfarcic/docker-flow-proxy


while true; do
    REPLICAS=$(docker service ls | grep swarm-listener | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep swarm-listener | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the swarm-listener service..."
        sleep 5
    fi
done

while true; do
    REPLICAS=$(docker service ls | grep proxy | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep proxy | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the proxy service..."
        sleep 5
    fi
done


docker service create --name elasticsearch \
    --mode global \
    --network elk \
    -p 9200:9200 \
    -e ES_JAVA_OPTS="-Dmapper.allow_dots_in_name=true" \
    --constraint "node.labels.elk == yes" \
    --reserve-memory 500m \
    elasticsearch:2.4


while true; do
    REPLICAS=$(docker service ls | grep elasticsearch | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep elasticsearch | awk '{print $4}')
    if [[ $REPLICAS == $ELK_NODE_COUNT"/"$ELK_NODE_COUNT || $REPLICAS_NEW == $ELK_NODE_COUNT"/"$ELK_NODE_COUNT ]]; then
        break
    else
        echo "Waiting for the elasticsearch service..."
        sleep 5
    fi
done



docker service create --name log-redis \
--network elk \
redis redis-server --requirepass redis

while true; do
    REPLICAS=$(docker service ls | grep log-redis | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep log-redis | awk '{print $4}')
    if [[ $REPLICAS == $LOG_REDIS_COUNT"/"$LOG_REDIS_COUNT || $REPLICAS_NEW == $LOG_REDIS_COUNT"/"$LOG_REDIS_COUNT ]]; then
        break
    else
        echo "Waiting for the log-redis service..."
        sleep 5
    fi
done


mkdir -p docker/logstash
cp conf/logstash.conf docker/logstash/logstash.conf

LOGSTASH_SOURCE=""
if [ "$ENV" = "remote" ]; then

    echo "copy logstash conf..."

    OLD_IFS="$IFS"
    IFS=","
    elk_nodes=($ELK_NODES_NUM)
    IFS="$OLD_IFS"
    for i in ${elk_nodes[@]}; do
        scp -r docker root@$(docker-machine ip swarm-$i):/
    done
    echo "copy logstash conf finished..."

    LOGSTASH_SOURCE="/docker/logstash" 
else
    LOGSTASH_SOURCE="$PWD/docker/logstash"
fi


docker service create --name logstash \
    --mount "type=bind,source=$LOGSTASH_SOURCE,target=/conf" \
    --mode global \
    --network elk \
    --constraint "node.labels.elk == yes" \
    -e LOGSPOUT=ignore \
    --reserve-memory 100m \
    logstash:2.4 logstash -f /conf/logstash.conf


while true; do
    REPLICAS=$(docker service ls | grep logstash | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep logstash | awk '{print $4}')
    if [[ $REPLICAS == $ELK_NODE_COUNT"/"$ELK_NODE_COUNT || $REPLICAS_NEW == $ELK_NODE_COUNT"/"$ELK_NODE_COUNT ]]; then
        break
    else
        echo "Waiting for the logstash service..."
        sleep 5
    fi
done

docker service create --name kibana \
    --network elk \
    --network proxy \
    -e ELASTICSEARCH_URL=http://elasticsearch:9200 \
    --reserve-memory 50m \
    --label com.df.notify=true \
    --label com.df.distribute=true \
    --label com.df.servicePath=/app/kibana,/bundles,/elasticsearch \
    --label com.df.port=5601 \
    kibana:4.6

while true; do
    REPLICAS=$(docker service ls | grep kibana | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep kibana | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the kibana service..."
        sleep 5
    fi
done


docker service create --name logspout \
    --network elk \
    --mode global \
    -e DEBUG=true \
    --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
    rtoma/logspout-redis-logstash redis://log-redis?password=redis


while true; do
    REPLICAS=$(docker service ls | grep logspout | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep logspout | awk '{print $4}')
    if [[ $REPLICAS == $NODE_COUNT"/"$NODE_COUNT || $REPLICAS_NEW == $NODE_COUNT"/"$NODE_COUNT ]]; then
        break
    else
        echo "Waiting for the logspout service..."
        sleep 5
    fi
done

echo ""
echo ">> The services are up and running inside the swarm cluster"
echo ""