# Custom Caddy build with the Route53 DNS-01 plugin - same reasoning and
# same pinned versions as docker-infisical/caddy/Dockerfile (see that repo):
# no runtime plugin loading in Caddy, and this container terminates TLS in
# front of NetBox, so an official base image plus a source build is
# preferred over a third-party pre-built image.
FROM caddy:2.11.4-builder AS builder
RUN xcaddy build v2.11.4 --with github.com/caddy-dns/route53@v1.6.2

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
