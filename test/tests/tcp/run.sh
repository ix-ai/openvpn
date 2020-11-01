#!/bin/bash
set -eE

trap cleanup ERR

function cleanup {
  if [ ! "${1}" == "OK" ]; then
    echo "The logs for ${NAME}"
    docker logs "${NAME}" || true
    echo "The logs for ${CLIENT}"
    docker logs "${CLIENT}" || true
  fi
  docker stop "${NAME}" || true
  docker rm "${NAME}" || true
  docker rm "${CLIENT}" || true
  docker volume rm "${OVPN_DATA}" || true
  iptables -D FORWARD 1  2>&1 || true
}

[ -n "${DEBUG+x}" ] && set -x

OVPN_DATA=basic-data
CLIENT=gitlab-client
IMG=registry.gitlab.com/ix.ai/openvpn
NAME="ovpn-basic"
CLIENT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../client")"

ip addr ls
SERV_IP=$(ip -4 -o addr show scope global  | awk '{print $4}' | sed -e 's:/.*::' | head -n1)

docker volume create "${OVPN_DATA}"

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_genconfig -u tcp://$SERV_IP 2>&1

# nopass is insecure
docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=GitLab-CI Test CA" $IMG ovpn_initpki nopass 2>&1

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG easyrsa build-client-full $CLIENT nopass  2>&1

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_getclient $CLIENT | tee $CLIENT_DIR/config.ovpn

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_listclients | grep $CLIENT

#
# Fire up the server
#
iptables -N DOCKER 2>&1|| echo 'Firewall already configured'
iptables -I FORWARD 1 -j DOCKER 2>&1|| echo 'Forward already configured'

docker run --log-driver local -d --name "${NAME}" -e "DEBUG=${DEBUG+1}" -v $OVPN_DATA:/etc/openvpn -p 443:1194/tcp --privileged $IMG ovpn_run --proto tcp

# Set the correct IP address for the server
COUNTER=0
while [ ${COUNTER} -le 10 ]; do
  ACTUAL_SERV_IP=$(docker inspect "${NAME}" --format '{{ .NetworkSettings.IPAddress }}')
  test -n "${ACTUAL_SERV_IP}" && break
  COUNTER=$(( ${COUNTER} + 1 ))
done
test -n "${ACTUAL_SERV_IP}" || false
sed -ie s:${SERV_IP}:${ACTUAL_SERV_IP}:g "${CLIENT_DIR}/config.ovpn"

# Fire up a client in a container
docker run --privileged --name "${CLIENT}" -e "DEBUG=${DEBUG+x}" --volume $CLIENT_DIR:/client $IMG /client/wait-for-connect.sh 2>&1

#
# Clean up after the run
#
cleanup OK

#
# Celebrate
#
cat <<EOF
 ___________
< it worked >
 -----------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\\
                ||----w |
                ||     ||
EOF
