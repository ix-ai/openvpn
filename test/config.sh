#!/bin/bash
set -e

testAlias+=(
	[ixdotai/openvpn]='openvpn'
)

imageTests+=(
	[openvpn]='
		udp
		tcp
		paranoid
  	conf_options
  	client
  	otp
		iptables
		revocation
	'
)
