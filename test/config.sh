#!/bin/bash
set -e

testAlias+=(
	[ixdotai/openvpn]='openvpn'
)

imageTests+=(
	[openvpn]='
		basic
		paranoid
  	conf_options
  	client
  	dual-proto
  	otp
		iptables
		revocation
	'
)
