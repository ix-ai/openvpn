# Smallest base image
FROM alpine:latest

LABEL maintainer="docker@ix.ai" \
      ai.ix.repository="ix.ai/openvpn"

ADD bin/* /usr/local/bin/

# Add support for OTP authentication using a PAM module
ADD ./otp/openvpn /etc/pam.d/

# Testing: pamtester
RUN set -eux; \
  \
  echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories; \
  apk --no-cache upgrade; \
  apk add --no-cache --update \
    openvpn \
    dnsmasq \
    iptables \
    bash \
    easy-rsa \
    openvpn-auth-pam \
    google-authenticator \
    pamtester \
    libqrencode \
  ; \
  ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin; \
  rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*; \
  chmod a+x /usr/local/bin/*

# Needed by scripts
ENV OPENVPN /etc/openvpn
ENV EASYRSA /usr/share/easy-rsa
ENV EASYRSA_PKI $OPENVPN/pki
ENV EASYRSA_VARS_FILE $OPENVPN/vars

# Prevents refused client connection because of an expired CRL
ENV EASYRSA_CRL_DAYS 3650

VOLUME ["/etc/openvpn"]

# Internally uses port 1194/udp, remap using `docker run -p 443:1194/tcp`
EXPOSE 1194/udp

CMD ["ovpn_run"]
