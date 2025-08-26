FROM envoyproxy/envoy:v1.31.0

COPY envoy.yaml /etc/envoy/envoy.yaml

HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD curl -sf http://127.0.0.1/ready || exit 1

