#!/bin/bash

set -e

SERV_IP=$(ip -4 -o addr show scope global  | awk '{print $4}' | sed -e 's:/.*::' | head -n1)
TEST1_OVPN="/etc/openvpn/test1.ovpn"

export SERVER_CONF="/etc/openvpn/openvpn.conf"
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="GitLab-CI Test CA"

# Function to fail
abort() { cat <<< "$@" 1>&2; false; }

# Check a config (haystack) for a given line (needle) exit with error if not
# found.
test_config() {

    local needle="${2}"
    local file="${1}"

    busybox grep -q "${needle}" "${file}"
    if [ $? -ne 0 ]; then
        abort "==> Config match not found: ${needle}"
    fi
}

# Check a config (haystack) for absence of given line (needle) exit with error
# if found.
test_not_config() {

    local needle="${2}"
    local file="${1}"

    busybox grep -vq "${needle}" "${file}"
    if [ $? -ne 0 ]; then
        abort "==> Config match found: ${needle}"
    fi
}


#
# Generate openvpn.config file
#

ovpn_genconfig -u udp://$SERV_IP -m 1337 2>&1

ovpn_initpki nopass 2>&1

easyrsa build-client-full test1 nopass 2>&1

ovpn_getclient test1 > "${TEST1_OVPN}"


#
# Simple test cases
#

# 1. client MTU
test_config "${TEST1_OVPN}" "^tun-mtu\s\+1337"


#
# Test udp client with tcp fallback
#
ovpn_genconfig -u udp://$SERV_IP -E "remote $SERV_IP 443 tcp" -E "remote vpn.example.com 443 tcp" 2>&1
# nopass is insecure
ovpn_initpki nopass 2>&1
easyrsa build-client-full client-fallback nopass 2>&1
ovpn_getclient client-fallback > "${TEST1_OVPN}"

test_config "${TEST1_OVPN}" "^remote\s\+$SERV_IP\s\+443\s\+tcp"
test_config "${TEST1_OVPN}" "^remote\s\+vpn.example.com\s\+443\s\+tcp"


#
# Test non-defroute config
#
ovpn_genconfig -d -u udp://$SERV_IP -r "172.33.33.0/24" -r "172.34.34.0/24" 2>&1
# nopass is insecure
ovpn_initpki nopass 2>&1
easyrsa build-client-full non-defroute nopass 2>&1
ovpn_getclient non-defroute > "${TEST1_OVPN}"

# The '!' inverts the match to test that the string isn't present
test_not_config "${TEST1_OVPN}" "^redirect-gateway\s\+def1"
