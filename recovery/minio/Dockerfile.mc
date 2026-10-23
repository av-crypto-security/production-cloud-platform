FROM busybox:1.36

COPY mc-binary /usr/bin/mc
COPY ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

RUN chmod 0755 /usr/bin/mc

ENTRYPOINT ["/usr/bin/mc"]
