#!/usr/bin/env bash

eval $(docker-machine env es-swarm-1)

docker network create --driver overlay elk

docker service create --name elasticsearch \
    --mode global \
    --network elk \
    -p 9200:9200 \
    --constraint "node.labels.elk == yes" \
    --reserve-memory 500m \
    elasticsearch:2.4

while true; do
    REPLICAS=$(docker service ps elasticsearch | grep es-swarm-2 | awk '{print $7}')
    echo "REPLICAS:"$REPLICAS
    A=$(docker service ps elasticsearch | grep es-swarm-2 | awk '{print $0}')
    echo $A
    if [[ $REPLICAS == "Running" ]]; then
        sleep 5
        echo "elasticsearch Running..."
        break
    else
        echo "Waiting for the elasticsearch service..."
        sleep 5
    fi
done

mkdir -p docker/logstash
cp conf/logstash.conf docker/logstash/logstash.conf
scp -r docker root@xxx.xxx.xxx.xxx:/
scp -r docker root@xxx.xxx.xxx.xxx:/


docker service create --name logstash \
    --mount "type=bind,source=/docker/logstash,target=/conf" \
    --mode global \
    --network elk \
    -e LOGSPOUT=ignore \
    --reserve-memory 100m \
    logstash:2.4 logstash -f /conf/logstash.conf

while true; do
    REPLICAS=$(docker service ps logstash | grep es-swarm-2 | awk '{print $7}')
    echo "REPLICAS:"$REPLICAS
     A=$(docker service ps logstash | grep es-swarm-2 | awk '{print $0}')
    echo $A
    if [[ $REPLICAS == "Running" ]]; then
        sleep 5
        echo "logstash Running..."
        break
    else
        echo "Waiting for the logstash service..."
        sleep 5
    fi
done

docker network create --driver overlay proxy

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
    REPLICAS=$(docker service ls | grep proxy | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep proxy | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the proxy service..."
        sleep 5
    fi
done

echo ""
echo ">> The services are up and running inside the swarm cluster"
echo ""

## open http://$(docker-machine ip es-swarm-1)/app/kibana
