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
  iptables -D FORWARD 1  2>&1 || true
}

[ -n "${DEBUG+x}" ] && set -x

OVPN_DATA="revocation-data"
CLIENT1="gitlab-client1"
CLIENT2="gitlab-client2"
IMG="registry.gitlab.com/ix.ai/openvpn"
NAME="ovpn-test"
CLIENT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../client")"
SERV_IP="$(ip -4 -o addr show scope global  | awk '{print $4}' | sed -e 's:/.*::' | head -n1)"

#
# Initialize openvpn configuration and pki.
#
docker volume create --name $OVPN_DATA
docker run --rm -v $OVPN_DATA:/etc/openvpn $IMG ovpn_genconfig -u udp://$SERV_IP 2>&1
docker run --rm -v $OVPN_DATA:/etc/openvpn -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=GitLab-CI Test CA" $IMG ovpn_initpki nopass 2>&1

#
# Fire up the server.
#
iptables -N DOCKER 2>&1|| echo 'Firewall already configured'
iptables -I FORWARD 1 -j DOCKER 2>&1|| echo 'Forward already configured'
docker run --log-driver local -d --name "${NAME}" -e "DEBUG=${DEBUG+1}" -v $OVPN_DATA:/etc/openvpn -p 1194:1194/udp --privileged $IMG

# Set the correct IP address for the server
COUNTER=0
while [ ${COUNTER} -le 10 ]; do
  ACTUAL_SERV_IP=$(docker inspect "${NAME}" --format '{{ .NetworkSettings.IPAddress }}')
  test -n "${ACTUAL_SERV_IP}" && break
  COUNTER=$(( ${COUNTER} + 1 ))
done
test -n "${ACTUAL_SERV_IP}" || false

#
# Test that easy_rsa generate CRLs with 'next publish' set to 3650 days.
#
DATE="$(docker exec $NAME openssl crl -nextupdate -noout -in /etc/openvpn/crl.pem)"
crl_next_update="$(echo ${DATE} | cut -d'=' -f2 | tr -d 'GMT' | xargs)"
crl_next_update="$(date -u -d "$crl_next_update" "+%s")"
now="$(docker exec $NAME date "+%s")"
crl_remain="$(( $crl_next_update - $now ))"
crl_remain="$(( $crl_remain / 86400 ))"
if (( $crl_remain < 3649 )); then
    echo "easy_rsa CRL next publish set to less than 3650 days." >&2
    false
fi

#
# Generate a first client certificate and configuration using $CLIENT1 as CN then revoke it.
#
docker exec $NAME easyrsa build-client-full $CLIENT1 nopass 2>&1
docker exec $NAME ovpn_getclient $CLIENT1 > $CLIENT_DIR/config.ovpn
docker exec $NAME bash -c "echo 'yes' | ovpn_revokeclient $CLIENT1 remove"
sed -ie s:${SERV_IP}:${ACTUAL_SERV_IP}:g "${CLIENT_DIR}/config.ovpn"

#
# Test that openvpn client can't connect using $CLIENT1 config.
#
if docker run --rm -v $CLIENT_DIR:/client --cap-add=NET_ADMIN --privileged $IMG /client/wait-for-connect.sh; then
    echo "Client was able to connect after revocation test #1." >&2
    false
fi

#
# Generate and revoke a second client certificate using $CLIENT2 as CN, then test for failed client connection.
#
docker exec $NAME easyrsa build-client-full $CLIENT2 nopass 2>&1
docker exec $NAME ovpn_getclient $CLIENT2 > $CLIENT_DIR/config.ovpn
docker exec $NAME bash -c "echo 'yes' | ovpn_revokeclient $CLIENT2 remove"
sed -ie s:${SERV_IP}:${ACTUAL_SERV_IP}:g "${CLIENT_DIR}/config.ovpn"

if docker run --rm -v $CLIENT_DIR:/client --cap-add=NET_ADMIN --privileged $IMG /client/wait-for-connect.sh; then
    echo "Client was able to connect after revocation test #2." >&2
    false
fi

#
# Restart the server
#
docker stop $NAME && docker start $NAME

#
# Test for failed connection using $CLIENT2 config again.
#
if docker run --rm -v $CLIENT_DIR:/client --cap-add=NET_ADMIN --privileged $IMG /client/wait-for-connect.sh; then
    echo "Client was able to connect after revocation test #3." >&2
    false
fi

#
# Stop the server and clean up
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
