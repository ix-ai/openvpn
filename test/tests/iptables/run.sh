#!/bin/bash
set -eE

trap trap-cleanup ERR

function trap-cleanup {
  cleanup
  exit 2
}

function cleanup {
  if [ ! "${1}" == "OK" ]; then
    echo "The logs for ${NAME}"
    docker logs "${NAME}" || true
  fi
  docker stop "${NAME}" || true
  docker rm "${NAME}" || true
  docker volume rm "${OVPN_DATA}" || true
}

[ -n "${DEBUG+x}" ] && set -x
OVPN_DATA=iptables-data
IMG="registry.gitlab.com/ix.ai/openvpn"
NAME="ovpn-iptables"
SERV_IP=$(ip -4 -o addr show scope global  | awk '{print $4}' | sed -e 's:/.*::' | head -n1)

# generate server config including iptables nat-ing
docker volume create --name $OVPN_DATA
docker run --rm -v $OVPN_DATA:/etc/openvpn $IMG ovpn_genconfig -u udp://$SERV_IP -N > /dev/null 2>&1
docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=GitLab-CI Test CA" $IMG ovpn_initpki nopass 2>&1

# Fire up the server
docker run -d --name $NAME -v $OVPN_DATA:/etc/openvpn --cap-add=NET_ADMIN $IMG

# check default iptables rules
docker exec $NAME bash -c 'source /etc/openvpn/ovpn_env.sh; eval iptables -t nat -C POSTROUTING -s $OVPN_SERVER -o eth0 -j MASQUERADE'

# append new setupIptablesAndRouting function to config
docker exec $NAME bash -c 'echo function setupIptablesAndRouting { iptables -t nat -A POSTROUTING -m comment --comment "test"\;} >> /etc/openvpn/ovpn_env.sh'

# kill server in preparation to modify config
docker kill $NAME
docker rm $NAME

# check that overridden function exists and that test iptables rules is active
docker run -d --name $NAME -v $OVPN_DATA:/etc/openvpn --cap-add=NET_ADMIN $IMG
docker exec $NAME bash -c 'source /etc/openvpn/ovpn_env.sh; type -t setupIptablesAndRouting && iptables -t nat -C POSTROUTING -m comment --comment "test"'

#
# kill server
#

cleanup OK
