FROM alpine:3.21

RUN apk add --no-cache openssh-server openssh-sftp-server shadow tini

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 2222
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
