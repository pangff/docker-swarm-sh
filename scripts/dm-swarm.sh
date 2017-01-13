#!/usr/bin/env bash
docker-machine rm es-swarm-1 es-swarm-2

docker-machine -D create --driver generic --generic-ip-address xxx.xxx.xxx.xxx --generic-ssh-user root es-swarm-1

docker-machine -D create --driver generic --generic-ip-address xxx.xxx.xxx.xxx --generic-ssh-user root es-swarm-2


eval $(docker-machine env es-swarm-1)

docker swarm init \
  --advertise-addr $(docker-machine ip es-swarm-1)

TOKEN=$(docker swarm join-token -q manager)

for i in 2; do
    eval $(docker-machine env es-swarm-$i)

    docker swarm join \
        --token $TOKEN \
        --advertise-addr $(docker-machine ip es-swarm-$i) \
        $(docker-machine ip es-swarm-1):2377
done


docker node update \
        --label-add elk=yes \
        es-swarm-2

echo ">> The swarm cluster is up and running"