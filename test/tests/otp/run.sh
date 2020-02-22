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

OVPN_DATA=data-otp
CLIENT=gitlab-client
IMG=ixdotai/openvpn
NAME="ovpn-otp"
OTP_USER=otp
CLIENT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../client")"

# Function to fail
abort() { cat <<< "$@" 1>&2; false; }

ip addr ls
SERV_IP=$(ip -4 -o addr show scope global  | awk '{print $4}' | sed -e 's:/.*::' | head -n1)

docker volume create "${OVPN_DATA}"

# Configure server with two factor authentication
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_genconfig -u udp://$SERV_IP -2 2>&1

# Ensure reneg-sec 0 in server config when two factor is enabled
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG cat /etc/openvpn/openvpn.conf | grep 'reneg-sec 0' || abort 'reneg-sec not set to 0 in server config'

# nopass is insecure
docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=GitLab-CI Test CA" $IMG ovpn_initpki nopass 2>&1

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG easyrsa build-client-full $CLIENT nopass 2>&1

# Generate OTP credentials for user named test, should return QR code for test user
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_otp_user $OTP_USER | tee $CLIENT_DIR/qrcode.txt
# Ensure a chart link is printed in client OTP configuration
grep 'https://www.google.com/chart' $CLIENT_DIR/qrcode.txt || abort 'Link to chart not generated'
grep 'Your new secret key is:' $CLIENT_DIR/qrcode.txt || abort 'Secret key is missing'
# Extract an emergency code from textual output, grepping for line and trimming spaces
OTP_TOKEN=$(grep -A1 'Your emergency scratch codes are' $CLIENT_DIR/qrcode.txt | tail -1 | tr -d '[[:space:]]')
# Token should be present
if [ -z $OTP_TOKEN ]; then
  abort "QR Emergency Code not detected"
fi

# Store authentication credentials in config file and tell openvpn to use them
echo -e "$OTP_USER\n$OTP_TOKEN" > $CLIENT_DIR/credentials.txt

# Override the auth-user-pass directive to use a credentials file
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_getclient $CLIENT | sed 's/auth-user-pass/auth-user-pass \/client\/credentials.txt/' | tee $CLIENT_DIR/config.ovpn

# Ensure reneg-sec 0 in client config when two factor is enabled
grep 'reneg-sec 0' $CLIENT_DIR/config.ovpn || abort 'reneg-sec not set to 0 in client config'

#
# Fire up the server
#
iptables -N DOCKER  2>&1 || echo 'Firewall already configured'
iptables -I FORWARD 1 -j DOCKER  2>&1 || echo 'Forward already configured'

docker run --log-driver local -d --name "${NAME}" -e "DEBUG=${DEBUG+1}" -v $OVPN_DATA:/etc/openvpn -p 1194:1194/udp --privileged $IMG

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
# Client either connected or timed out, kill server
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
