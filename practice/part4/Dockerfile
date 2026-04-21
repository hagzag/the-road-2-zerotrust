FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    wireguard-tools \
    iproute2 \
    iputils-ping \
    iperf3 \
    tcpdump \
    coreutils

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
