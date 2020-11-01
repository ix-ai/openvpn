#!/bin/bash
set -e

testAlias+=(
	[registry.gitlab.com/ix.ai/openvpn]='openvpn'
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
