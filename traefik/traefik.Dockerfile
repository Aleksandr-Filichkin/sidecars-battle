FROM traefik:v2.10

# Static and dynamic configs
COPY traefik.yml /etc/traefik/traefik.yml
COPY traefik-dynamic.yml /etc/traefik/traefik-dynamic.yml

