#!/bin/bash

fwd_dns="8.8.8.8"

echo "Provisioning Docker ..."
echo "***********************"
echo " "
sudo sh -c 'echo "DOCKER_OPTS=\"-H tcp://0.0.0.0:4444 -H unix:///var/run/docker.sock\"" >> /etc/default/docker'
sudo restart docker
sleep 5
echo " "
echo "Starting containers ..."
echo "***********************"
echo " "

echo "cleaning up ..."
echo "***************"
# clean previous containers in host
sudo docker stop $(sudo docker ps -qa)
sudo docker rm $(sudo docker ps -qa)
echo " "

# first find the docker0 interface assigned IP
DOCKER0_IP=$(ip -o -4 addr list docker0 | awk '{split($4,a,"/"); print a[1]}')
    
# then launch a skydns container to register our network addresses
dns=$(sudo docker run -d \
    -p $DOCKER0_IP:53:53/udp \
    --name skydns \
    crosbymichael/skydns \
    -nameserver $fwd_dns:53 \
    -domain docker)
echo "Starting dns registry ..."
echo "*************************"
echo $dns
echo " "

sleep 5

# inspect the container to extract the IP of our DNS server
DNS_IP=$(sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' skydns)

# launch skydock as our listener of container events in order to register/deregister all the names on skydns
skydock=$(sudo docker run -d \
	-v /var/run/docker.sock:/docker.sock \
	--name skydock \
	crosbymichael/skydock \
	-ttl 30 \
	-environment dev \
	-s /docker.sock \
	-domain docker \
	-skydns "http://$DNS_IP:8080")
echo "Starting docker event listener ..."
echo "**********************************"
echo $skydock
echo " "

sleep 5

# boot the graphite instance
graphite=$(sudo docker run -d \
  --name metrics \
  -h metrics.graphite.dev.docker \
  -p 8180:80 \
  -p 2003:2003 \
  --dns=$DNS_IP \
  sitespeedio/graphite)
echo "Starting graphite instance metrics.graphite.dev.docker ..."
echo "**********************************************************"
echo $graphite
echo " "

# fix permissions for dockerized node
sudo chmod -R a+r /vagrant/services

# boot the node instance
node=$(sudo docker run -d \
  --name services \
  -h services.node.dev.docker \
  -p 3000:3000 \
  -v /vagrant/services:/services \
  -w /services \
  --dns=$DNS_IP \
  library/node node /services/services.js)
echo "Starting node instance services.node.dev.docker ..."
echo "***************************************************"
echo $node
echo " "

sleep 5

# boot the nginx instance
nginx=$(sudo docker run -itd \
	--name=static \
	-h static.nginx.dev.docker \
	-p 80:80 \
    --dns=$DNS_IP \
    -v /vagrant/static:/static:ro \
	-v /vagrant/nginx-conf/nginx.conf:/etc/nginx/nginx.conf:ro \
	library/nginx:1.9.6)
echo "Starting nginx instance static.nginx.dev.docker ..."
echo "***************************************************"
echo $nginx
echo " "
